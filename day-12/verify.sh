#!/usr/bin/env bash
# Day 12 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

base=http://localhost:8212
http() { curl -s -m 5 "$@"; }
aws() {
  docker run --rm --network day12-net \
    -e AWS_ENDPOINT_URL=http://day12-moto:5000 -e AWS_DEFAULT_REGION=eu-west-3 \
    -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_PAGER= \
    amazon/aws-cli "$@"
}
running() { [ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
all_running() { running day12-mongo && running day12-api && running day12-moto && running day12-caddy; }
status_of() { http -o /dev/null -w '%{http_code}' "$@"; }
bucket_has_build() {
  local keys
  keys=$(aws s3api list-objects-v2 --bucket day12-site --query 'Contents[].Key' --output text)
  [[ $keys == *app.js* && $keys == *index.html* ]]
}
page_from_bucket() { [ "$(status_of $base/)" = "200" ] && http $base/ | grep -qF '<div id="root">'; }
page_type() { [[ $(http -o /dev/null -w '%{content_type}' $base/) == text/html* ]]; }
bundle_is_react() {
  local size
  size=$(http -H 'Accept-Encoding: identity' $base/app.js | wc -c)
  [ "$size" -gt 100000 ] && http -H 'Accept-Encoding: identity' $base/app.js | grep -q 'createRoot'
}
bundle_type() { [[ $(http -o /dev/null -w '%{content_type}' $base/app.js) == *javascript* ]]; }
served_by_header() { http -I $base/ | grep -qi '^x-served-by: caddy'; }
gzip_on() { http -H 'Accept-Encoding: gzip' -I $base/app.js | grep -qi '^content-encoding: gzip'; }
health() { [ "$(http $base/api/health)" = '{"status":"ok","database":"connected"}' ]; }
unknown_static() { [ "$(status_of $base/nothing-here)" = "404" ]; }
unknown_api() { [ "$(status_of $base/api/nothing-here)" = "404" ] && http $base/api/nothing-here | grep -q '"error"'; }
bad_note() { [ "$(status_of -X POST -H 'Content-Type: application/json' -d '{"text":""}' $base/api/notes)" = "400" ]; }
note_roundtrip() {
  local token="verify-$RANDOM-$RANDOM"
  [ "$(status_of -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$token\"}" $base/api/notes)" = "201" ] &&
    http $base/api/notes | grep -qF "$token"
}
note_in_mongo() {
  local token="mongo-$RANDOM-$RANDOM"
  http -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$token\"}" $base/api/notes >/dev/null
  [ "$(docker exec day12-mongo mongosh --quiet --eval "db.getSiblingDB('notes').notes.countDocuments({text:'$token'})")" = "1" ]
}
api_stateless() {
  local before after
  before=$(http $base/api/notes)
  docker restart day12-api >/dev/null
  for _ in $(seq 1 30); do [ "$(status_of $base/api/health)" = "200" ] && break; sleep 1; done
  after=$(http $base/api/notes)
  [ -n "$before" ] && [ "$before" = "$after" ]
}
frontend_update() {
  local token="release-$RANDOM-$RANDOM"
  echo "$token" | docker run --rm -i --network day12-net \
    -e AWS_ENDPOINT_URL=http://day12-moto:5000 -e AWS_DEFAULT_REGION=eu-west-3 \
    -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test amazon/aws-cli \
    s3 cp - s3://day12-site/version.txt --acl public-read >/dev/null &&
    [ "$(http $base/version.txt)" = "$token" ]
}
only_caddy_published() {
  [ -z "$(docker port day12-mongo)" ] && [ -z "$(docker port day12-api)" ] && [ -z "$(docker port day12-moto)" ] &&
    docker port day12-caddy | grep -q ':8212$'
}
# A throwaway container tries to open a TCP connection to the backend and the database.
reaches() { # reaches <network> <address> <port>
  docker run --rm --network "$1" ubuntu timeout 3 bash -c "echo > /dev/tcp/$2/$3" >/dev/null 2>&1
}
isolated_network() {
  local api_ip mongo_ip
  api_ip=$(docker container inspect -f '{{(index .NetworkSettings.Networks "day12-net").IPAddress}}' day12-api 2>/dev/null) || return 1
  mongo_ip=$(docker container inspect -f '{{(index .NetworkSettings.Networks "day12-net").IPAddress}}' day12-mongo 2>/dev/null) || return 1
  # Inside the network the same connections work, so a refusal elsewhere means something.
  reaches day12-net "$api_ip" 3000 && reaches day12-net "$mongo_ip" 27017 &&
    ! reaches bridge "$api_ip" 3000 && ! reaches bridge "$mongo_ip" 27017
}

step "Day 12 verification"
echo "the four parts"
check "mongo, api, moto (bucket) and caddy are running" all_running
check "the bucket day12-site holds index.html and app.js" bucket_has_build
echo "the front door (Caddy, port 8212)"
check "/ is served from the bucket as an HTML page" page_from_bucket
check "/ has the content type text/html" page_type
check "/app.js is a React bundle (over 100 KB, contains createRoot)" bundle_is_react
check "/app.js has a JavaScript content type" bundle_type
check "responses carry the CDN stand-in header" served_by_header
check "responses are gzip-compressed on request" gzip_on
check "a path that is not in the bucket gives 404" unknown_static
echo "the backend behind /api"
check "/api/health reports the database as connected" health
check "an unknown /api path gives a JSON 404 from the backend" unknown_api
check "an empty note is rejected with 400" bad_note
check "a note posted through /api shows up in the list" note_roundtrip
check "the note is stored in MongoDB" note_in_mongo
check "restarting the backend loses no notes" api_stateless
echo "the frontend can be updated alone"
check "a file uploaded to the bucket is served at once" frontend_update
echo "what is exposed"
check "only Caddy publishes a port" only_caddy_published
check "backend and database accept connections from day12-net but not from another network" isolated_network
summary

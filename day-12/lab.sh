#!/usr/bin/env bash
# Day 12 lab: a full-stack deployment (slides 248-264), without an AWS account.
#
#   slides                              here
#   React frontend built, put on S3     React built in a node container, uploaded to a bucket in moto
#   Node.js backend on App Runner       the backend image run as a container
#   DocumentDB                          a MongoDB container
#   CloudFront in front of both         Caddy: /api/* to the backend, everything else to the bucket
#
# Safe to run more than once: it rebuilds everything it owns (day12-*).
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

work=$PWD/.work
http() { curl -s -m 5 "$@"; }

# The real AWS CLI, pointed at the day 12 bucket server. moto accepts any credentials here.
aws() {
  docker run --rm --network day12-net -v "$work/dist:/dist:ro" \
    -e AWS_ENDPOINT_URL=http://day12-moto:5000 -e AWS_DEFAULT_REGION=eu-west-3 \
    -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_PAGER= \
    amazon/aws-cli "$@"
}

step "1. Start clean (only day 12's own containers, network and image)"
docker rm -f day12-caddy day12-api day12-moto day12-mongo >/dev/null 2>&1 || true
docker network rm day12-net >/dev/null 2>&1 || true
docker image rm day12-api:1 >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$work/dist"
run docker network create day12-net

step "2. The database: a MongoDB container for DocumentDB (slides 252, 255)"
echo "DocumentDB is Amazon's MongoDB-compatible service, so the backend does not change: it only gets a different address."
run docker run -d --restart unless-stopped --name day12-mongo --network day12-net mongo
for _ in $(seq 1 60); do
  docker exec day12-mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q '^1$' && break
  sleep 1
done
echo "MongoDB answers: $(docker exec day12-mongo mongosh --quiet --eval 'db.version()')"

step "3. The backend as an image, run like App Runner would (slides 252-253)"
run docker build -t day12-api:1 api
run docker run -d --restart unless-stopped --name day12-api --network day12-net -e MONGO_URL=mongodb://day12-mongo:27017 day12-api:1
for _ in $(seq 1 30); do
  docker logs day12-api 2>&1 | grep -q 'connected to MongoDB' && break
  sleep 1
done
docker logs day12-api 2>&1 | sed 's/^/  api log: /'

step "4. The frontend: build React into static files (slide 257)"
echo "The slides point out that a frontend is only files, so it does not need a running server."
echo "esbuild bundles React and the app into dist/app.js. The build runs in a node container:"
run docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_update_notifier=false \
  -v "$PWD/frontend:/src:ro" -v "$work/dist:/out" node:26-slim \
  sh -c 'cp -r /src /tmp/build && cd /tmp/build && npm install --no-audit --no-fund --loglevel=error && npm run build && cp dist/app.js public/index.html /out/'
ls -l "$work/dist" | sed 's/^/  /'

step "5. The bucket: an S3-compatible store (slide 258)"
echo "moto's S3 holds the files. Nothing outside the network can reach it directly."
run docker run -d --restart unless-stopped --name day12-moto --network day12-net motoserver/moto
for _ in $(seq 1 30); do
  aws s3 ls >/dev/null 2>&1 && break
  sleep 1
done
run aws s3 mb s3://day12-site
echo "Upload the build with the real AWS CLI, as the slides' pipeline would. The objects are public-read, because Caddy fetches them without credentials:"
run aws s3 sync /dist s3://day12-site --delete --acl public-read
run aws s3 ls s3://day12-site

step "6. The single front door: Caddy in place of CloudFront (slides 260-262)"
echo "Requests starting with /api go to the backend. Every other path is read from the bucket."
cat Caddyfile | sed 's/^/  | /'
run docker run -d --restart unless-stopped --name day12-caddy --network day12-net -p 8212:80 \
  -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" caddy
for _ in $(seq 1 30); do
  [ "$(http -o /dev/null -w '%{http_code}' http://localhost:8212/)" = "200" ] && break
  sleep 1
done

step "7. Using it: one address for everything"
echo "\$ curl -si http://localhost:8212/   (the page, from the bucket)"
http -si http://localhost:8212/ | grep -iE '^(HTTP|content-type|cache-control|x-served-by)|<div id="root">' | sed 's/^/  /'
echo "\$ curl -si http://localhost:8212/app.js   (the React bundle, from the bucket)"
http -si -H 'Accept-Encoding: identity' http://localhost:8212/app.js | grep -iE '^(HTTP|content-type|content-length)' | sed 's/^/  /'
echo "\$ curl http://localhost:8212/api/health   (the backend)"
echo "  $(http http://localhost:8212/api/health)"
echo "\$ curl -X POST http://localhost:8212/api/notes -d '{\"text\":\"hello from the lab\"}'"
echo "  $(http -X POST -H 'Content-Type: application/json' -d '{"text":"hello from the lab"}' http://localhost:8212/api/notes)"
echo "\$ curl http://localhost:8212/api/notes"
echo "  $(http http://localhost:8212/api/notes)"
echo "A path that is neither in the bucket nor under /api:"
echo "  /nothing-here -> HTTP $(http -o /dev/null -w '%{http_code}' http://localhost:8212/nothing-here)"

step "8. The data is in MongoDB, not in the backend (slides 252, 255)"
echo "Notes stored: $(docker exec day12-mongo mongosh --quiet --eval 'db.getSiblingDB("notes").notes.countDocuments()')"
echo "Restart the backend. It is stateless, so the notes are still there:"
run docker restart day12-api
for _ in $(seq 1 30); do
  [ "$(http -o /dev/null -w '%{http_code}' http://localhost:8212/api/health)" = "200" ] && break
  sleep 1
done
echo "  $(http http://localhost:8212/api/notes)"

step "9. Update only the frontend: no backend deployment needed (slide 257)"
echo "release 2, uploaded $(date -u +%H:%M:%SZ)" >"$work/dist/version.txt"
run aws s3 cp /dist/version.txt s3://day12-site/version.txt --acl public-read
echo "Served at once: $(http http://localhost:8212/version.txt)"

step "10. What is reachable from outside"
echo "Published ports:"
docker ps --filter name=day12- --format '  {{.Names}}: {{if .Ports}}{{.Ports}}{{else}}(none){{end}}'

step "Done"
echo "Open http://$(public_name):8212 in a browser on the Mac."
echo "Slide 264 deletes everything at the end because DocumentDB and CloudFront cost money. Here: day-12/cleanup.sh."
echo "Next: setup/run.sh day-12/verify.sh"

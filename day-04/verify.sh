#!/usr/bin/env bash
# Day 04 checks. Run after lab.sh and deploy.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

html=/usr/share/nginx/html
work=$PWD/.work

running() { [ "$(docker container inspect -f '{{.State.Running}}' "$1")" = "true" ]; }
no_mounts() { [ "$(docker container inspect -f '{{len .Mounts}}' day04-web)" = "0" ]; }
web_serves_site() { curl -s -m 3 http://localhost:8081 | grep -qF 'day-04 site'; }
web_serves_css() { [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://localhost:8081/style.css)" = "200" ]; }
stopped_copy() { curl -s -m 3 http://localhost:8081/stopped.txt | grep -qF 'copied while the container was stopped'; }
deployed_matches() { [ -f "$HOME/app/index.html" ] && curl -s -m 3 http://localhost:8081 | cmp -s - "$HOME/app/index.html"; }
is_bind_mount() { [ "$(docker container inspect -f '{{range .Mounts}}{{.Type}}:{{.Destination}}{{end}}' day04-bind)" = "bind:$html" ]; }
live_edit() {
  local token="live-$RANDOM-$RANDOM"
  echo "$token" >"$work/dev-site/verify-token.txt"
  local got
  got=$(curl -s -m 3 http://localhost:3000/verify-token.txt)
  rm -f "$work/dev-site/verify-token.txt"
  [ "$got" = "$token" ]
}
container_file_on_host() { grep -qF 'written by the container' "$work/dev-site/from-container.txt"; }
readonly_rejects_write() { ! docker run --rm -v "$work/dev-site:/data:ro" ubuntu touch /data/should-fail.txt; }
mount_needs_existing_path() { ! docker run --rm --mount "type=bind,source=$work/does-not-exist,destination=/data" ubuntu true; }
v_created_folder() { [ -d "$work/missing-b" ]; }
temp_gone() { [ -z "$(docker container ls -aq --filter name=day04-mount --filter name=day04-ro)" ]; }

step "Day 04 verification"
echo "docker cp (production style)"
check "day04-web is running" running day04-web
check "day04-web has no mounts: its files were copied in" no_mounts
check "port 8081 serves the day 4 site" web_serves_site
check "the stylesheet was copied too" web_serves_css
check "a file copied while the container was stopped is served" stopped_copy
check "deploy.sh was run: ~/app/index.html is exactly what port 8081 serves" deployed_matches
echo "bind mounts (development style)"
check "day04-bind is running" running day04-bind
check "day04-bind mounts a host folder at $html" is_bind_mount
check "a new file on the host is served on port 3000 immediately" live_edit
check "a file written by the container exists on the host" container_file_on_host
check "a read-only mount rejects writes from the container" readonly_rejects_write
check "--mount refuses a host path that does not exist" mount_needs_existing_path
check "-v created the missing host folder" v_created_folder
check "temporary containers were removed" temp_gone
summary

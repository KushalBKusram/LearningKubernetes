#!/usr/bin/env bash
# Day 06 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

cfg() { docker image inspect day06-app --format "$1"; }
has_image() { docker image inspect "$1"; }
workdir_is_app() { [ "$(cfg '{{.Config.WorkingDir}}')" = "/app" ]; }
exposes_3000() { cfg '{{range $p, $_ := .Config.ExposedPorts}}{{$p}}{{end}}' | grep -qx '3000/tcp'; }
cmd_is_exec_form() { [ "$(cfg '{{json .Config.Cmd}}')" = '["node","server.js"]' ]; }
image_has() { docker run --rm day06-app test -e "/app/$1"; }
image_lacks() { ! docker run --rm day06-app test -e "/app/$1"; }
second_build_cached() { [ "$(docker build -t day06-app app 2>&1 | grep -c 'CACHED')" -ge 4 ]; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' day06-app)" = "true" ]; }
restart_policy() { [ "$(docker container inspect -f '{{.HostConfig.RestartPolicy.Name}}' day06-app)" = "unless-stopped" ]; }
page_ok() { curl -s -m 3 http://localhost:8101 | grep -qF 'Hello from the Node app'; }
info_ok() { [ "$(curl -s -m 3 http://localhost:8101/api/info | jq -r .version)" = "1.0.0" ]; }
health_ok() { [ "$(curl -s -m 3 http://localhost:8101/health | jq -r .status)" = "ok" ]; }
stateless() { [ -z "$(docker diff day06-app)" ]; }
cmd_default() { local out; out=$(docker run --rm day06-cmd); grep -qE '^v[0-9]+\.' <<<"$out"; }
cmd_replaced() { [ "$(docker run --rm day06-cmd echo replaced)" = "replaced" ]; }
entrypoint_default() { local out; out=$(docker run --rm day06-entrypoint); grep -qE '^v[0-9]+\.' <<<"$out"; }
entrypoint_gets_args() { [ "$(docker run --rm day06-entrypoint -p '6 * 7')" = "42" ]; }
copy_keeps_archive() { docker run --rm day06-add test -f /copied/site.tar.gz; }
add_unpacks_archive() { docker run --rm day06-add test -f /added/site/index.html; }
temp_gone() { [ -z "$(docker container ls -aq --filter name=day06-random)" ]; }

step "Day 06 verification"
echo "the image"
check "image day06-app exists" has_image day06-app
check "WORKDIR is /app" workdir_is_app
check "EXPOSE documents port 3000" exposes_3000
check "CMD is [\"node\", \"server.js\"] in exec form" cmd_is_exec_form
check "RUN npm ci put node_modules into the image" image_has node_modules/express
check ".dockerignore kept NOTES.md out of the image" image_lacks NOTES.md
check ".dockerignore kept the Dockerfile out of the image" image_lacks Dockerfile
check "an unchanged build is served from the cache" second_build_cached
echo "the container"
check "day06-app is running" running
check "restart policy is unless-stopped" restart_policy
check "port 8101 serves the app's page" page_ok
check "/api/info reports version 1.0.0" info_ok
check "/health reports ok" health_ok
check "the container has written no files (stateless)" stateless
echo "CMD, ENTRYPOINT, COPY and ADD"
check "CMD demo: default command prints the Node.js version" cmd_default
check "CMD demo: a command after the image name replaces CMD" cmd_replaced
check "ENTRYPOINT demo: default parameters print the Node.js version" entrypoint_default
check "ENTRYPOINT demo: arguments are passed to node (6 * 7 = 42)" entrypoint_gets_args
check "COPY left the archive packed" copy_keeps_archive
check "ADD unpacked the archive" add_unpacks_archive
check "temporary container was removed" temp_gone
summary

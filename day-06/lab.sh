#!/usr/bin/env bash
# Day 06 lab: Dockerfiles and a stateless app container (slides 133-157).
# Runs on the server. Safe to run more than once: it recreates its own containers.
#
# Leaves running:
#   day06-app   port 8101   the Node.js app, built from app/Dockerfile
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./build-steps.sh
need_docker

work=$PWD/.work # scratch space on the server, recreated on every run
info() { curl -s -m 3 http://localhost:8101/api/info; }

docker rm -f day06-app day06-random >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$work"

step "1. The build context and its Dockerfile (slides 140-142)"
run ls -a app
echo
echo "app/Dockerfile without its comments:"
grep -v -e '^#' -e '^$' app/Dockerfile | sed 's/^/  /'

step "2. docker build: Dockerfile -> image (slides 142-143)"
echo "One line per build step. A step marked (cached) is reused from an earlier build;"
echo "on a machine that has never built this image, every step runs:"
build -t day06-app app

step "3. Building again uses the cache: nothing changed, so no step runs again"
build -t day06-app app

step "4. What the instructions produced (slides 145-157)"
echo "One line per instruction, newest first:"
docker image history day06-app --format '  {{.Size}}\t{{.CreatedBy}}' | head -7
echo
docker image inspect day06-app --format '  WORKDIR: {{.Config.WorkingDir}}{{"\n"}}  EXPOSE:  {{range $port, $_ := .Config.ExposedPorts}}{{$port}} {{end}}{{"\n"}}  CMD:     {{.Config.Cmd}}'
echo
echo "Files in /app inside the image. NOTES.md and the Dockerfile are missing because of .dockerignore;"
echo "node_modules is there because 'RUN npm ci' created it during the build:"
run docker run --rm day06-app ls -a /app

step "5. Run it as a stateless container, as App Runner would (slides 136-138)"
run docker run -d --name day06-app -p 8101:3000 --restart unless-stopped day06-app
sleep 2
info | jq .
echo "Files this container has written since it started: '$(docker diff day06-app)' (none: it is stateless)"
echo
echo "Because it keeps no data, it can be thrown away and replaced at any time:"
first=$(info | jq -r .hostname)
docker rm -f day06-app >/dev/null
run docker run -d --name day06-app -p 8101:3000 --restart unless-stopped day06-app
sleep 2
echo "Container before: $first, container now: $(info | jq -r .hostname), same answer: $(info | jq -r .greeting)"

step "6. CMD: a default that 'docker run' can replace (slide 147)"
run docker build -q -t day06-cmd demos/cmd
run docker run --rm day06-cmd
run docker run --rm day06-cmd echo "CMD was replaced by this command"

step "7. ENTRYPOINT: the program stays, CMD becomes its parameters (slide 149)"
run docker build -q -t day06-entrypoint demos/entrypoint
run docker run --rm day06-entrypoint
echo "Arguments after the image name replace CMD and are handed to node:"
run docker run --rm day06-entrypoint -p '6 * 7'

step "8. EXPOSE documents a port; -P publishes exposed ports on random host ports (slide 151)"
run docker run -d --name day06-random -P day06-app
run docker port day06-random
docker rm -f day06-random >/dev/null
echo "Publishing a chosen port with -p, as in step 5, is the usual way."

step "9. COPY versus ADD (slide 145)"
mkdir -p "$work/add/site"
echo "<h1>inside the archive</h1>" >"$work/add/site/index.html"
tar -czf "$work/add/site.tar.gz" -C "$work/add" site
rm -r "$work/add/site"
run docker build -q -t day06-add -f demos/add/Dockerfile "$work/add"
echo "COPY kept the archive as a file:"
run docker run --rm day06-add ls -R /copied
echo "ADD unpacked it:"
run docker run --rm day06-add ls -R /added

step "Done"
echo "day06-app  http://localhost:8101"
echo "Next: setup/run.sh day-06/verify.sh"

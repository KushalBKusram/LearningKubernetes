#!/usr/bin/env bash
# Day 04 lab: getting files into containers (slides 98-114).
# Runs on the server. Safe to run more than once: it recreates its own containers.
#
# Leaves running:
#   day04-web   port 8081   files copied in with docker cp   (the "production" container)
#   day04-bind  port 3000   files bind-mounted from the host (the "development" container)
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

html=/usr/share/nginx/html
work=$PWD/.work # scratch space on the server, recreated on every run
heading() { curl -s -m 3 "$1" | grep -o '<h1>.*</h1>' || echo "(no answer)"; }

docker rm -f day04-web day04-bind day04-mount day04-ro >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$work"

step "1. Files written in a container live in its writable layer (slide 100)"
run docker run -d --restart unless-stopped --name day04-web -p 8081:80 nginx
sleep 1
run docker exec day04-web sh -c 'echo "only in this container" > /tmp/note.txt'
echo "What this container has changed compared with its image (A = added, C = changed):"
run docker diff day04-web
echo "Its own data is tiny; the rest ('virtual') is the shared, read-only image:"
run docker container ls -s --filter name=day04-web --format '  {{.Names}}: {{.Size}}'

step "2. docker cp: out of a container (slide 102)"
run docker cp "day04-web:$html/index.html" "$work/default-index.html"
echo "Copied to the host. Its heading: $(grep -m1 -o '<h1>.*</h1>' "$work/default-index.html")"

step "3. docker cp: into a container (slide 102)"
echo "Before: $(heading http://localhost:8081)"
run docker cp site/. "day04-web:$html/"
echo "After:  $(heading http://localhost:8081)"

step "4. docker cp also works while the container is stopped (slide 102)"
run docker stop day04-web
echo "copied while the container was stopped" >"$work/stopped.txt"
run docker cp "$work/stopped.txt" "day04-web:$html/stopped.txt"
run docker start day04-web
sleep 1
echo "http://localhost:8081/stopped.txt -> $(curl -s -m 3 http://localhost:8081/stopped.txt)"

step "5. Bind mount with -v: the container sees a host directory (slides 104, 106)"
cp -r site "$work/dev-site"
run docker run -d --restart unless-stopped --name day04-bind -p 3000:80 -v "$work/dev-site:$html" nginx
sleep 1
echo "Before: $(heading http://localhost:3000)"
echo "Edit the file on the host. Nothing is copied and nothing is restarted:"
run sed -i 's|<h1>.*</h1>|<h1>Edited on the host, visible at once</h1>|' "$work/dev-site/index.html"
echo "After:  $(heading http://localhost:3000)"
echo
echo "It works in the other direction too. A file written by the container appears on the host:"
run docker exec day04-bind sh -c "echo 'written by the container' > $html/from-container.txt"
run cat "$work/dev-site/from-container.txt"

step "6. The same bind mount with --mount (slide 105)"
run docker run -d --name day04-mount --mount "type=bind,source=$work/dev-site,destination=$html" nginx
docker container inspect day04-mount \
  --format '{{range .Mounts}}  type={{.Type}}  {{.Source}} -> {{.Destination}}  writable={{.RW}}{{"\n"}}{{end}}'

step "7. The difference: a host path that does not exist (slide 106)"
echo "--mount fails:"
if out=$(docker run --rm --mount "type=bind,source=$work/missing-a,destination=/data" ubuntu ls /data 2>&1); then
  echo "  UNEXPECTED: it worked"
else
  echo "$out" | grep -i 'error' | head -1 | sed 's/^/  /'
fi
echo "-v creates the folder on the host instead:"
run docker run --rm -v "$work/missing-b:/data" ubuntu ls -ld /data
run ls -ld "$work/missing-b"

step "8. Read-only bind mount (slide 108)"
run docker run -d --name day04-ro -v "$work/dev-site:$html:ro" nginx
echo "Writing from the container is refused:"
if out=$(docker exec day04-ro touch "$html/new.txt" 2>&1); then
  echo "  UNEXPECTED: the write worked"
else
  echo "  $out"
fi
echo "Changes on the host are still seen by the container immediately:"
echo "changed on the host" >"$work/dev-site/host-change.txt"
run docker exec day04-ro cat "$html/host-change.txt"

docker rm -f day04-mount day04-ro >/dev/null

step "Done"
echo "day04-web  (docker cp)   http://localhost:8081"
echo "day04-bind (bind mount)  http://localhost:3000"
echo "Next, on the Mac: day-04/deploy.sh, then setup/run.sh day-04/verify.sh"

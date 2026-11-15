#!/usr/bin/env bash
# Day 02 exercise (slide 55): change the page nginx serves.
#   - background color: lightgray
#   - heading: "Welcome to nginx in docker"
# The slides edit the file with nano inside the container. This does the same
# edit with sed so it can run unattended.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

page=/usr/share/nginx/html/index.html

if [ "$(docker container inspect -f '{{.State.Running}}' day02-nginx 2>/dev/null)" != "true" ]; then
  echo "day02-nginx is not running. Run day-02/lab.sh first." >&2
  exit 1
fi

step "Before"
docker exec day02-nginx grep -E '<body|<h1>' "$page"

step "Edit $page inside the container"
run docker exec day02-nginx sed -i \
  -e 's|<body>|<body style="background-color: lightgray">|' \
  -e 's|<h1>Welcome to nginx!</h1>|<h1>Welcome to nginx in docker</h1>|' \
  "$page"

step "After"
docker exec day02-nginx grep -E '<body|<h1>' "$page"

echo
echo "Open http://$(public_name):8888 in a browser on the Mac."

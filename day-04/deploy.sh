#!/usr/bin/env bash
# Day 04 deployment (slides 112-114). Run ON THE MAC, not on the server:
#
#   day-04/deploy.sh
#
# Step 1: transfer the website to the server with scp.
# Step 2: copy it into the running container with docker cp.
#
# The slides use:  scp -r . ubuntu@13.37.244.236:/home/ubuntu/app
# Here the server is the machine named by COURSE_HOST (see setup/config.sh), so the files go to ~/app there.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../setup/config.sh"
HOST=$COURSE_HOST
cd "$here/site"

if [ "$(ssh "$HOST" "docker container inspect -f '{{.State.Running}}' day04-web" 2>/dev/null)" != "true" ]; then
  echo "The container day04-web is not running on $HOST. Run this first: setup/run.sh day-04/lab.sh" >&2
  exit 1
fi

echo "== Step 1: transfer the files to the server (slide 113)"
ssh "$HOST" 'mkdir -p ~/app'
echo "\$ scp -r . $HOST:app"
scp -r . "$HOST:app"
ssh "$HOST" 'ls -l ~/app'

echo
echo "== Step 2: copy the files into the container (slide 114)"
echo "\$ docker cp ~/app/. day04-web:/usr/share/nginx/html/      (run on $HOST)"
ssh "$HOST" 'docker cp ~/app/. day04-web:/usr/share/nginx/html/'

echo
echo "== Result, fetched from this Mac"
fqdn=$(ssh -G "$HOST" 2>/dev/null | awk '$1 == "hostname" { print $2 }')
url="http://$fqdn:8081"
echo "$url"
curl -s -m 8 "$url" | grep -E -o '<title>.*</title>|<h1>.*</h1>' | sed 's/^/  /'

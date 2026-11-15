#!/usr/bin/env bash
# Removes what day 13 created on the server: containers, volumes (and the data
# in them), the demo image and the scratch folder. Pulled images are kept.
set -uo pipefail
cd "$(dirname "$0")"

for name in day13-nginx day13-anon day13-declared day13-mariadb; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f -v "$name" >/dev/null && echo "removed container $name"
  fi
done

for volume in day13-nginx-vol day13-auto-vol day13-mariadb-vol; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker volume rm "$volume" >/dev/null && echo "removed volume $volume"
  fi
done

if docker image inspect day13-volume-demo >/dev/null 2>&1; then
  docker image rm day13-volume-demo >/dev/null && echo "removed image day13-volume-demo"
fi

if [ -d .work ]; then
  rm -rf .work && echo "removed day-13/.work"
fi

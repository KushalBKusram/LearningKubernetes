#!/usr/bin/env bash
# Removes what day 5 created on the server: its containers, Caddy's volume
# (including its certificate authority) and the scratch folder. Images are kept.
set -uo pipefail
cd "$(dirname "$0")"

for name in day05-dns day05-caddy; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f -v "$name" >/dev/null && echo "removed container $name"
  fi
done

if docker volume inspect day05-caddy-data >/dev/null 2>&1; then
  docker volume rm day05-caddy-data >/dev/null && echo "removed volume day05-caddy-data"
fi

if [ -d .work ]; then
  rm -rf .work && echo "removed day-05/.work"
fi

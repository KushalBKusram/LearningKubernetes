#!/usr/bin/env bash
# Removes what day 14 created on the server: containers, networks, the volume
# (and the MongoDB data in it) and the scratch folder. Pulled images are kept.
set -uo pipefail
cd "$(dirname "$0")"

for name in day14-a day14-b day14-c day14-host day14-none day14-mongo day14-express; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f -v "$name" >/dev/null && echo "removed container $name"
  fi
done

for net in day14-net day14-other day14-mongo-net; do
  if docker network inspect "$net" >/dev/null 2>&1; then
    docker network rm "$net" >/dev/null && echo "removed network $net"
  fi
done

if docker volume inspect day14-mongo-vol >/dev/null 2>&1; then
  docker volume rm day14-mongo-vol >/dev/null && echo "removed volume day14-mongo-vol"
fi

if [ -d .work ]; then
  rm -rf .work && echo "removed day-14/.work"
fi

#!/usr/bin/env bash
# Slide 264: delete the setup. Removes day 12's containers, network, image and build output.
# Base images (node, mongo, caddy, moto, aws-cli) are kept.
set -uo pipefail
cd "$(dirname "$0")"

for name in day12-caddy day12-api day12-moto day12-mongo; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed container $name"
  fi
done
if docker network inspect day12-net >/dev/null 2>&1; then
  docker network rm day12-net >/dev/null && echo "removed network day12-net"
fi
if docker image inspect day12-api:1 >/dev/null 2>&1; then
  docker image rm day12-api:1 >/dev/null && echo "removed image day12-api:1"
fi
if [ -d .work ]; then
  rm -rf .work && echo "removed day-12/.work"
fi

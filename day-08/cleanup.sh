#!/usr/bin/env bash
# Removes what day 8 created on the server: the moto server (and with it every
# user, policy, role and instance it recorded), its network and the stored keys.
# Images are kept.
set -uo pipefail
cd "$(dirname "$0")"

if docker container inspect day08-moto >/dev/null 2>&1; then
  docker rm -f day08-moto >/dev/null && echo "removed container day08-moto"
fi
if docker network inspect day08-net >/dev/null 2>&1; then
  docker network rm day08-net >/dev/null && echo "removed network day08-net"
fi
if [ -d .work ]; then
  rm -rf .work && echo "removed day-08/.work"
fi

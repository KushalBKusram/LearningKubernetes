#!/usr/bin/env bash
# Removes what day 11 created: its containers and networks on the server, and its
# VPC objects in the moto server (if that is still running). Images are kept.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./common.sh

for name in day11-web day11-db day11-outsider; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed container $name"
  fi
done
for net in day11-public day11-private; do
  if docker network inspect "$net" >/dev/null 2>&1; then
    docker network rm "$net" >/dev/null && echo "removed network $net"
  fi
done
if use_admin 2>/dev/null; then
  teardown_vpc >/dev/null 2>&1 && echo "removed the day11 VPC objects from the moto server"
fi

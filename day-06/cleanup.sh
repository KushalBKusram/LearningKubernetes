#!/usr/bin/env bash
# Removes what day 6 created on the server: its containers, its demo images
# and its scratch folder.
#
# The image day06-app is kept, because days 7 and 10 use it. To remove it too:
#   docker image rm day06-app
set -uo pipefail
cd "$(dirname "$0")"

for name in day06-app day06-random; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed container $name"
  fi
done

for image in day06-cmd day06-entrypoint day06-add; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    docker image rm "$image" >/dev/null && echo "removed image $image"
  fi
done

if [ -d .work ]; then
  rm -rf .work && echo "removed day-06/.work"
fi

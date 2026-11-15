#!/usr/bin/env bash
# Removes what day 10 created on the server: its containers, its images and its
# scratch folder. The pulled base images (node:26-slim, node:26-alpine,
# python:alpine) are kept, because other days may use them.
set -uo pipefail
cd "$(dirname "$0")"

for name in day10-app day10-extract; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed container $name"
  fi
done

for image in day10-app:debian day10-app:slim day10-app:alpine day10-ts:single day10-ts:multistage; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    docker image rm "$image" >/dev/null && echo "removed image $image"
  fi
done

if [ -d .work ]; then
  rm -rf .work && echo "removed day-10/.work"
fi

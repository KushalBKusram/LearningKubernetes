#!/usr/bin/env bash
# Removes the containers created on day 2. Images are kept.
set -uo pipefail
for name in day02-hidden day02-nginx day02-python day02-created; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed $name"
  fi
done

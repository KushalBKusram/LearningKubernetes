#!/usr/bin/env bash
# Removes what day 7 created on the server: the registry container and the
# images and tags it made. Day 9 pushes to this registry, so run day 9's
# cleanup first if you want to keep its images.
#
# Kept unless you say otherwise: the registry's data volume (the pushed images) and
# the password in ~/.course. To remove them too:
#   day-07/cleanup.sh --all
set -uo pipefail
cd "$(dirname "$0")"

for name in day07-registry day07-registry-open; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed container $name"
  fi
done

for image in localhost:5000/day06-app:1.0.0 localhost:5000/day06-app:latest \
  localhost:5000/day07-multiarch:1 day07-hello-arm64 hello-world:linux; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    docker image rm "$image" >/dev/null 2>&1 && echo "removed image $image"
  fi
done

docker logout localhost:5000 >/dev/null 2>&1 && echo "logged out of localhost:5000"

if [ -d .work ]; then
  rm -rf .work && echo "removed day-07/.work"
fi

if [ "${1:-}" = "--all" ]; then
  docker volume rm day07-registry-data >/dev/null 2>&1 && echo "removed volume day07-registry-data"
  rm -f "$HOME/.course/registry-password" "$HOME/.course/registry-htpasswd" && echo "removed the registry password files"
fi

#!/usr/bin/env bash
# Removes what day 9 created on the server: the container, the local images and
# the scratch folder holding both Git repositories.
#
# The images already pushed to the day 7 registry stay there: that registry does
# not allow deleting images through its API, and removing day 7's volume
# (day-07/cleanup.sh --all) clears them.
set -uo pipefail
cd "$(dirname "$0")"

if docker container inspect day09-app >/dev/null 2>&1; then
  docker rm -f day09-app >/dev/null && echo "removed container day09-app"
fi

for image in $(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^localhost:5000/day09-app:'); do
  docker image rm "$image" >/dev/null 2>&1 && echo "removed image $image"
done

if [ -d .work ]; then
  rm -rf .work && echo "removed day-09/.work (both repositories)"
fi

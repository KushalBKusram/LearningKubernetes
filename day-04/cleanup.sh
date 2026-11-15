#!/usr/bin/env bash
# Removes what day 4 created on the server: its containers, its scratch folder,
# and the deployed copy in ~/app. Images are kept.
set -uo pipefail
cd "$(dirname "$0")"

for name in day04-web day04-bind day04-mount day04-ro; do
  if docker container inspect "$name" >/dev/null 2>&1; then
    docker rm -f "$name" >/dev/null && echo "removed container $name"
  fi
done

if [ -d .work ]; then
  rm -rf .work && echo "removed day-04/.work"
fi

# Only delete ~/app if it is the folder deploy.sh created.
if [ -f "$HOME/app/index.html" ] && grep -qF 'day-04 site' "$HOME/app/index.html"; then
  rm -rf "$HOME/app" && echo "removed ~/app"
elif [ -e "$HOME/app" ]; then
  echo "left ~/app alone: it does not look like the day 4 deployment"
fi

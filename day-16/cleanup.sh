#!/usr/bin/env bash
# Removes what day 16 created on the server: the compose project "day16" with its
# volume (Caddy's certificates) and the image day16-bad-app. Pulled images are kept.
set -uo pipefail
cd "$(dirname "$0")"

docker compose --project-name day16 down --volumes --remove-orphans 2>&1 | sed 's/^/compose: /'
if docker image inspect day16-bad-app >/dev/null 2>&1; then
  docker image rm day16-bad-app >/dev/null && echo "removed image day16-bad-app"
fi

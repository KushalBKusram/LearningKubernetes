#!/usr/bin/env bash
# Removes what day 15 created on the server: the compose project "day15" with its
# volumes (and the data in them), and the generated .env. Pulled images are kept.
set -uo pipefail
cd "$(dirname "$0")"

docker compose --project-name day15 down --volumes --remove-orphans 2>&1 | sed 's/^/compose: /'
rm -f .env && echo "removed day-15/.env"

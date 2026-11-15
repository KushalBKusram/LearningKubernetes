#!/usr/bin/env bash
# Removes the container created on day 3. Images are kept.
set -uo pipefail
if docker container inspect day03-apache >/dev/null 2>&1; then
  docker rm -f day03-apache >/dev/null && echo "removed day03-apache"
fi

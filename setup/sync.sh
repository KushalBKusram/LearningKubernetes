#!/usr/bin/env bash
# Run on the Mac. Copies this project to the server (~/Projects/Kubernetes).
# The Mac folder is the source of truth; nothing is deleted on the server.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/setup/config.sh"
HOST=$COURSE_HOST
REMOTE_DIR=$COURSE_REMOTE_DIR

ssh "$HOST" "mkdir -p '$REMOTE_DIR'"
rsync -az \
  --exclude 'slides.pdf' --exclude '.git/' --exclude '.DS_Store' --exclude '.claude/' \
  --exclude 'setup/local.env' \
  "$here/" "$HOST:$REMOTE_DIR/"
echo "Synced to $HOST:~/$REMOTE_DIR"

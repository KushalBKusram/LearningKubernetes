#!/usr/bin/env bash
# Run on the Mac. Syncs the project, then runs one script on the server.
#
#   setup/run.sh day-01/lab.sh
#   setup/run.sh day-01/verify.sh
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: setup/run.sh <path-to-script-in-project> [args...]" >&2
  exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
. "$here/config.sh"
HOST=$COURSE_HOST
REMOTE_DIR=$COURSE_REMOTE_DIR

"$here/sync.sh" >/dev/null
script=$1
shift
ssh "$HOST" "cd '$REMOTE_DIR' && bash '$script' $*"

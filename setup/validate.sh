#!/usr/bin/env bash
# Run on the Mac. Runs the checks of every built day on the server and
# prints one summary line per day.
#
#   setup/validate.sh          all days that have a verify.sh
#   setup/validate.sh 04       one day, with the full list of checks
set -uo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/setup/config.sh"
HOST=$COURSE_HOST
REMOTE_DIR=$COURSE_REMOTE_DIR
cd "$here"

"$here/setup/sync.sh" >/dev/null

if [ $# -ge 1 ]; then
  ssh "$HOST" "cd '$REMOTE_DIR' && bash 'day-$1/verify.sh'"
  exit $?
fi

failed=0
for script in day-*/verify.sh; do
  day=${script%/verify.sh}
  out=$(ssh "$HOST" "cd '$REMOTE_DIR' && bash '$script'" 2>&1)
  totals=$(echo "$out" | grep -E '^[0-9]+ passed, [0-9]+ failed$' | tail -1)
  if [ -z "$totals" ]; then
    totals="did not finish: $(echo "$out" | tail -1)"
    failed=1
  elif ! echo "$totals" | grep -q ' 0 failed$'; then
    failed=1
  fi
  printf '%s  %s\n' "$day" "$totals"
  echo "$out" | grep -E '^  FAIL' || true
done
exit $failed

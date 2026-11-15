#!/usr/bin/env bash
# Helper for the labs of days 6, 7 and 10. Source this file; do not run it.
#
# build ARGS...   runs "docker build ARGS..." and prints one line per build step
#                 (marked "cached" when it came from the build cache) instead of
#                 BuildKit's full progress log. On failure the full log is shown.
build() {
  printf '\033[2m$ docker build %s\033[0m\n' "$*"
  local log
  if ! log=$(docker build "$@" 2>&1); then
    echo "$log"
    return 1
  fi
  echo "$log" | awk '
    /^#[0-9]+ \[/ && !/\[internal\]/ {
      id = $1
      sub(/^#[0-9]+ /, "")
      sub(/@sha256:[0-9a-f]+/, "")
      if (!(id in desc)) ids[++n] = id
      desc[id] = $0
    }
    /^#[0-9]+ CACHED/ { cached[$1] = 1 }
    END {
      for (i = 1; i <= n; i++)
        printf "  %s%s\n", desc[ids[i]], (ids[i] in cached) ? "   (cached)" : ""
    }'
}

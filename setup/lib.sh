#!/usr/bin/env bash
# Shared helpers for the day labs. Source this file; do not run it.

# kubectl, kind and helm were installed without sudo into ~/.local/bin, which
# non-interactive SSH sessions do not have on their PATH.
export PATH="$HOME/.local/bin:$PATH"

# The name a browser on your computer uses to reach this server, for the URLs the labs print.
# Order: COURSE_DOMAIN if set, else this machine's Tailscale name, else its hostname.
public_name() {
  if [ -n "${COURSE_DOMAIN:-}" ]; then
    echo "$COURSE_DOMAIN"
    return
  fi
  local n=""
  if command -v tailscale >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    n=$(tailscale status --self --peers=false --json 2>/dev/null | jq -r '.Self.DNSName // empty' 2>/dev/null | sed 's/\.$//')
  fi
  echo "${n:-$(hostname -f 2>/dev/null || hostname)}"
}

# Print a section heading.
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# Print a command the way the slides show it, then run it.
run() {
  local shown="" arg
  for arg in "$@"; do
    case $arg in
      "" | *[!A-Za-z0-9_./:=,@%+-]*) shown+=" '${arg//\'/\'\\\'\'}'" ;; # quote it, as you would type it
      *) shown+=" $arg" ;;
    esac
  done
  printf '\033[2m$%s\033[0m\n' "$shown"
  "$@"
}

# check "description" command...   -> counts a pass or a fail, never aborts.
PASS=0
FAIL=0
check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$desc"
  fi
}

# Print the totals; exit status is non-zero if anything failed.
summary() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

# Stop early when the Kubernetes tools are missing.
need_k8s_tools() {
  local tool
  for tool in kubectl kind helm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "$tool is not installed in ~/.local/bin on this machine." >&2
      exit 1
    fi
  done
}

# Stop early with a clear message when Docker is missing or not usable.
need_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is not usable here. Run setup/install-docker.sh on the server first," >&2
    echo "then open a new SSH session so the docker group applies." >&2
    exit 1
  fi
}

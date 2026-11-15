#!/usr/bin/env bash
# Removes everything day 20 created: the namespace day20 and all of its workloads.
# The cluster stays. Day 21 builds on a fresh namespace, so it does not need day 20's workloads.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_docker
need_k8s_tools

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  command kubectl --context "$CTX" delete namespace day20 --ignore-not-found
fi

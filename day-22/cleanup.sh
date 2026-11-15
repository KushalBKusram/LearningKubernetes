#!/usr/bin/env bash
# Removes everything day 22 created: the namespace day22 (workloads, Services, Secret).
# The cluster stays. Frees the node ports 30080 and 30081.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_docker
need_k8s_tools

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  command kubectl --context "$CTX" delete namespace day22 --ignore-not-found
fi

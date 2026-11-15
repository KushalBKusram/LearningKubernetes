#!/usr/bin/env bash
# Removes what day 19 created. By default the cluster stays, because days 20-23 use it.
#
#   day-19/cleanup.sh          remove the day 19 namespace and its Helm release
#   day-19/cleanup.sh --all    also delete the whole kind cluster "course" (days 20-23 need it)
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./k8s-lib.sh
need_docker
need_k8s_tools

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  K8S_NAMESPACE=day19
  helm uninstall day19-headlamp >/dev/null 2>&1 && echo "removed Helm release day19-headlamp"
  command kubectl --context "$CTX" delete clusterrolebinding day19-dashboard-admin --ignore-not-found
  command kubectl --context "$CTX" delete namespace day19 --ignore-not-found
fi

if [ "${1:-}" = "--all" ]; then
  kind delete cluster --name "$CLUSTER"
fi

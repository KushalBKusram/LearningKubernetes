#!/usr/bin/env bash
# Removes everything day 23 created: the namespace day23 (workloads and claims), the cluster-wide
# PersistentVolume and StorageClass, and the data directories on the node.
# The cluster stays.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_docker
need_k8s_tools

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  command kubectl --context "$CTX" delete namespace day23 --ignore-not-found
  command kubectl --context "$CTX" delete pv day23-local-pv --ignore-not-found
  command kubectl --context "$CTX" delete storageclass hostpath --ignore-not-found
  docker exec "$NODE" rm -rf /mnt/day23-hostpath /mnt/day23-pv && echo "removed /mnt/day23-* on the node"
fi
exit 0

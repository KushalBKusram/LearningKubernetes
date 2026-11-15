#!/usr/bin/env bash
# Removes everything day 21 created: the namespace day21, and the image day21-app:1.0 from
# Docker and from the cluster's node. The cluster stays.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_docker
need_k8s_tools

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  command kubectl --context "$CTX" delete namespace day21 --ignore-not-found
  docker exec "$NODE" crictl rmi docker.io/library/day21-app:1.0 >/dev/null 2>&1 && echo "removed day21-app:1.0 from the node"
fi
docker image rm day21-app:1.0 >/dev/null 2>&1 && echo "removed day21-app:1.0 from Docker"
exit 0

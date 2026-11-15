#!/usr/bin/env bash
# Removes what day 24 added to the eks cluster, or the whole cluster with --cluster.
# The eks cluster is also used by day 25; day-25/teardown.sh removes the cluster.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./env.sh

if docker container inspect day24-manual-lb >/dev/null 2>&1; then
  docker rm -f day24-manual-lb >/dev/null && echo "removed container day24-manual-lb"
fi

if cluster_exists && [ "${1:-}" != "--cluster" ]; then
  kc delete -f ingress.yaml -f hello.yaml -f nginx.yaml --ignore-not-found
  kc delete secret nginx-eks-tls --ignore-not-found
  hc uninstall nginx-ingress -n nginx-ingress 2>/dev/null
  kc delete namespace nginx-ingress metallb-system --ignore-not-found
fi

if [ "${1:-}" = "--cluster" ] && cluster_exists; then
  kind delete cluster --name "$EKS_CLUSTER" --kubeconfig "$KUBECONFIG"
  rm -f "$KUBECONFIG"
fi

if [ -d .work ]; then rm -rf .work && echo "removed day-24/.work"; fi
if docker image inspect day24-hello:1 >/dev/null 2>&1; then
  docker image rm day24-hello:1 >/dev/null && echo "removed image day24-hello:1"
fi

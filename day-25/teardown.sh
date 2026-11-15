#!/usr/bin/env bash
# Day 25 teardown: delete the eks cluster the way slide 550 describes, in its order:
#   1. the cluster's own resources (workloads, then volumes), 2. the load balancers,
#   3. the cluster, 4. what is left outside it.
# On AWS step 4 means NAT gateways, elastic IPs, security groups and the VPC; here it is
# a Docker container, an image and a kubeconfig file.
#
#   setup/run.sh day-25/teardown.sh
#
# After this, day-24/lab.sh and day-25/lab.sh build everything again.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-24/env.sh
need_docker
need_k8s_tools

step "Before"
if cluster_exists; then
  run kubectl --context "$EKS_CONTEXT" get pods,pvc,pv -A -o wide
else
  echo "The cluster '$EKS_CLUSTER' does not exist; only the leftovers are cleaned up."
fi

if cluster_exists; then
  step "1. Workloads, then volumes (slide 550: remove the EFS volumes, then the EBS volumes)"
  kc delete -f wordpress.yaml -f mysql.yaml -f zone-demo.yaml --ignore-not-found --wait=true
  kc delete pvc data-mysql-0 --ignore-not-found --wait=true
  hc uninstall efs -n efs 2>/dev/null || true
  kc delete namespace efs --ignore-not-found --wait=true
  echo "Volumes left in the cluster:"
  kc get pv 2>&1

  step "2. Load balancers and ingress (slide 550: remove the remaining load balancers)"
  kc delete -f ../day-24/ingress.yaml -f ../day-24/hello.yaml -f ../day-24/nginx.yaml --ignore-not-found --wait=true
  kc delete secret nginx-eks-tls --ignore-not-found
  hc uninstall nginx-ingress -n nginx-ingress 2>/dev/null || true
  kc delete namespace nginx-ingress metallb-system --ignore-not-found --wait=true

  step "3. The cluster (eksctl delete cluster)"
  run kind delete cluster --name "$EKS_CLUSTER" --kubeconfig "$KUBECONFIG"
fi

step "4. Leftovers outside the cluster (slide 550: load balancer, kubeconfig, images)"
if docker container inspect day24-manual-lb >/dev/null 2>&1; then
  docker rm -f day24-manual-lb >/dev/null && echo "removed container day24-manual-lb"
fi
if [ -e "$KUBECONFIG" ]; then rm -f "$KUBECONFIG" && echo "removed $KUBECONFIG"; fi
if [ -d ../day-24/.work ]; then rm -rf ../day-24/.work && echo "removed day-24/.work"; fi
if docker image inspect day24-hello:1 >/dev/null 2>&1; then
  docker image rm day24-hello:1 >/dev/null && echo "removed image day24-hello:1"
fi

step "After"
echo "kind clusters:       $(kind get clusters 2>/dev/null | tr '\n' ' ')"
echo "eks node containers: $(docker ps -a --format '{{.Names}}' | grep -c "^$EKS_CLUSTER-" || true)"
echo "day24/day25 containers: $(docker ps -a --format '{{.Names}}' | grep -cE '^day2[45]-' || true)"
if cluster_exists; then
  echo "The cluster still exists." >&2
  exit 1
fi
echo "The eks cluster is gone. Run day-24/lab.sh and day-25/lab.sh to build it again."

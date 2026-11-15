#!/usr/bin/env bash
# Day 19 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./k8s-lib.sh
need_cluster
K8S_NAMESPACE=day19

# contains <text>: reads all of stdin, then looks for the text. (grep -q stops reading early, so the
# program feeding it can die of SIGPIPE, and with "pipefail" a match could be reported as a failure,
# or, in a negated check, a failure as a pass.)
contains() { local data; data=$(cat); [[ $data == *"$1"* ]]; }
node_ready() { [ "$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = "True" ]; }
# Days 24 and 25 add a second cluster ("eks"), so only require that "course" exists with one node.
only_cluster() { kind get clusters | grep -qx course && [ "$(kind get nodes --name course | grep -c .)" = "1" ]; }
cp_pod() { kubectl -n kube-system get pod "$1-$NODE" -o jsonpath='{.status.phase}' | grep -qx Running; }
kube_proxy_ok() { [ "$(kubectl -n kube-system get ds kube-proxy -o jsonpath='{.status.numberReady}')" = "1" ]; }
coredns_ok() { [ "$(kubectl -n kube-system get deploy coredns -o jsonpath='{.status.readyReplicas}')" -ge 1 ]; }
port_mapped() { docker port "$NODE" 30080/tcp | grep -q ':30080$'; }
my_ubuntu_gone() { ! kubectl get pod my-ubuntu >/dev/null 2>&1 && ! kubectl get pod my-ubuntu2 >/dev/null 2>&1; }
helm_release() { [ "$(helm list -o json | jq -r '.[] | select(.name=="day19-headlamp") | .status')" = "deployed" ]; }
headlamp_ready() { [ "$(kubectl get deploy day19-headlamp -o jsonpath='{.status.readyReplicas}')" = "1" ]; }
dashboard_page() { curl -s -m 5 http://localhost:30089 | contains 'Headlamp'; }
token_works() {
  local token
  token=$(kubectl create token dashboard-admin --duration=10m) || return 1
  [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -k -H "Authorization: Bearer $token" "$(kubectl config view --minify --context "$CTX" -o jsonpath='{.clusters[0].cluster.server}')/api/v1/namespaces/day19")" = "200" ]
}
no_token_rejected() {
  [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -k "$(kubectl config view --minify --context "$CTX" -o jsonpath='{.clusters[0].cluster.server}')/api/v1/namespaces/day19")" = "401" ] ||
    [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -k "$(kubectl config view --minify --context "$CTX" -o jsonpath='{.clusters[0].cluster.server}')/api/v1/namespaces/day19")" = "403" ]
}
restart_policy_never() {
  kubectl run verify-never --restart=Never --image=ubuntu -- true >/dev/null 2>&1 || return 1
  local phase="" i
  for i in $(seq 1 45); do
    phase=$(kubectl get pod verify-never -o jsonpath='{.status.phase}')
    [ "$phase" = "Succeeded" ] && break
    sleep 2
  done
  local restarts
  restarts=$(kubectl get pod verify-never -o jsonpath='{.status.containerStatuses[0].restartCount}')
  kubectl delete pod verify-never --wait=false >/dev/null 2>&1
  [ "$phase" = "Succeeded" ] && [ "$restarts" = "0" ]
}
restart_policy_always() {
  kubectl run verify-always --image=ubuntu -- true >/dev/null 2>&1 || return 1
  local restarts=0 i
  for i in $(seq 1 60); do
    restarts=$(kubectl get pod verify-always -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)
    [ "${restarts:-0}" -ge 1 ] && break
    sleep 2
  done
  kubectl delete pod verify-always --wait=false >/dev/null 2>&1
  [ "${restarts:-0}" -ge 1 ]
}

step "Day 19 verification"
echo "cluster"
check "the kind cluster 'course' exists with a single node" only_cluster
check "the node is Ready" node_ready
check "node port 30080 is published on the server" port_mapped
check "kube-apiserver is running" cp_pod kube-apiserver
check "etcd is running" cp_pod etcd
check "kube-scheduler is running" cp_pod kube-scheduler
check "kube-controller-manager is running" cp_pod kube-controller-manager
check "kube-proxy is ready" kube_proxy_ok
check "CoreDNS is ready" coredns_ok
echo "pods and restart policies"
check "the lab's pods were deleted" my_ubuntu_gone
check "restart policy Always: a finished pod is started again" restart_policy_always
check "restart policy Never: a finished pod stays finished" restart_policy_never
echo "Helm and the dashboard"
check "Helm release day19-headlamp is deployed" helm_release
check "Headlamp pod is ready" headlamp_ready
check "the dashboard page loads on port 30089" dashboard_page
check "a token for the dashboard-admin user is accepted by the API server" token_works
check "the API server rejects a request without a token" no_token_rejected
summary

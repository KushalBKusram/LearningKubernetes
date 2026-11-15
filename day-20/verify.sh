#!/usr/bin/env bash
# Day 20 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_cluster
K8S_NAMESPACE=day20

jp() { kubectl get "$1" -o jsonpath="$2"; } # jp <object> <jsonpath>
deployment_ready() { [ "$(jp deployment/wordpress-deployment '{.status.readyReplicas}')" = "3" ] && [ "$(jp deployment/wordpress-deployment '{.spec.replicas}')" = "3" ]; }
pods_count() { [ "$(kubectl get pods -l app=wordpress --no-headers | grep -c Running)" = "3" ]; }
rs_history() { [ "$(kubectl get replicaset -l app=wordpress --no-headers | wc -l)" -ge 2 ]; }
one_rs_active() { [ "$(kubectl get replicaset -l app=wordpress --no-headers | awk '$2 > 0' | wc -l)" = "1" ]; }
rollout_history() { [ "$(kubectl rollout history deployment/wordpress-deployment | grep -cE '^[0-9]+')" -ge 2 ]; }
deployment_label() { [ -n "$(kubectl get deployments -l app=wordpress,version=1.1 --no-headers)" ]; }
pod_has_label() { [ "$(kubectl get pods -l app=wordpress --no-headers | wc -l)" -ge 3 ]; }
selector_value() { [ "$(jp deployment/wordpress-deployment '{.spec.selector.matchLabels.app}')" = "wordpress" ]; }
selector_immutable() {
  sed 's/app: wordpress # how the Deployment finds.*/app: wordpress-v2/' deployment.yaml >.verify-selector.yaml
  local out
  out=$(kubectl apply -f .verify-selector.yaml 2>&1)
  local rc=$?
  rm -f .verify-selector.yaml
  [ $rc -ne 0 ] && echo "$out" | grep -qi immutable
}
every_replica_answers() {
  local pod
  for pod in $(kubectl get pods -l app=wordpress -o name); do
    kubectl exec "$pod" -- bash -c 'exec 3<>/dev/tcp/127.0.0.1/80; printf "GET / HTTP/1.0\r\n\r\n" >&3; head -n1 <&3' | grep -qE '^HTTP/1\.[01] [0-9]{3}' || return 1
  done
}
rollout_undone() { [ -z "$(jp deployment/wordpress-deployment '{.spec.template.spec.containers[0].env}')" ]; }
self_heal() {
  local victim
  victim=$(kubectl get pods -l app=wordpress -o name | head -1)
  kubectl delete "$victim" --wait=false >/dev/null || return 1
  local i
  for i in $(seq 1 60); do
    sleep 2
    [ "$(jp deployment/wordpress-deployment '{.status.readyReplicas}')" = "3" ] &&
      [ "$(kubectl get pods -l app=wordpress --no-headers | grep -c Running)" = "3" ] && return 0
  done
  return 1
}
no_helper_workloads() { [ -z "$(kubectl get job,daemonset,replicaset.apps/day20-replicaset,pod/day20-pod --ignore-not-found --no-headers 2>/dev/null | grep -E 'day20-')" ]; }
no_forward_left() { ! pgrep -f 'port-forward deployment/wordpress-deployment' >/dev/null; }

step "Day 20 verification"
echo "Deployment"
check "wordpress-deployment has 3 of 3 replicas ready" deployment_ready
check "exactly 3 WordPress pods are running" pods_count
check "pods carry the label app=wordpress" pod_has_label
check "the Deployment is found by app=wordpress,version=1.1 (label patched by the lab)" deployment_label
check "the selector is app=wordpress, without a version" selector_value
check "changing spec.selector is rejected as immutable" selector_immutable
echo "Rolling update"
check "the Deployment owns 2 or more ReplicaSets (old one kept for undo)" rs_history
check "only one ReplicaSet has pods" one_rs_active
check "rollout history lists 2 or more revisions" rollout_history
check "the rollback removed the APP_VERSION variable" rollout_undone
echo "behaviour"
check "every replica answers HTTP on port 80" every_replica_answers
check "deleting a pod is repaired: 3 ready replicas again" self_heal
echo "clean-up"
check "the demo pod, ReplicaSet, Job and DaemonSet are gone" no_helper_workloads
check "no port-forward is left running" no_forward_left
summary

#!/usr/bin/env bash
# Day 21 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_cluster
K8S_NAMESPACE=day21

# contains <text>: reads all of stdin, then looks for the text. (grep -q stops reading early, so the
# program feeding it can die of SIGPIPE, and with "pipefail" a match could be reported as a failure,
# or, in a negated check, a failure as a pass.)
contains() { local data; data=$(cat); [[ $data == *"$1"* ]]; }
jp() { kubectl get "$1" -o jsonpath="$2"; }
sts_ready() { [ "$(jp statefulset/mariadb-statefulset '{.status.readyReplicas}')" = "1" ]; }
pod_name_sticky() { [ "$(kubectl get pods -l app=mariadb -o jsonpath='{.items[0].metadata.name}')" = "mariadb-statefulset-0" ]; }
db_login() { kubectl exec mariadb-statefulset-0 -- sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" wordpress -e "select 1"'; }
secret_exists() { [ "$(jp secret/my-mariadb-secret '{.data.username}' | base64 -d)" = "admin" ]; }
secret_is_base64_only() { [ "$(jp secret/my-mariadb-secret '{.data.password}' | base64 -d)" = "secretpassword" ]; }
no_plaintext_password() { ! kubectl get statefulset mariadb-statefulset -o yaml | contains 'secretpassword'; }
uses_secret_ref() { [ "$(jp statefulset/mariadb-statefulset '{.spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.name}')" = "my-mariadb-secret" ]; }
pull_policy_set() { [ "$(jp statefulset/mariadb-statefulset '{.spec.template.spec.containers[0].imagePullPolicy}')" = "IfNotPresent" ]; }
app_ready() { [ "$(jp deployment/day21-app '{.status.readyReplicas}')" = "2" ]; }
node_has_app_image() { node_has_image docker.io/library/day21-app:1.0; }
app_answers() {
  local pod
  pod=$(kubectl get pods -l app=day21-app -o jsonpath='{.items[0].metadata.name}')
  kubectl exec "$pod" -- python -c "import urllib.request, json; d = json.load(urllib.request.urlopen('http://127.0.0.1:8000')); assert d['greeting'] == 'hello from a Deployment' and d['db_user'] == 'admin' and d['db_password_length'] == 14"
}
app_never_shows_password() {
  local pod
  pod=$(kubectl get pods -l app=day21-app -o jsonpath='{.items[0].metadata.name}')
  ! kubectl exec "$pod" -- python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000').read().decode())" | contains secretpassword
}
app_pull_never_ok() { # a Pod with imagePullPolicy Never starts, because the node has the image
  kubectl delete pod verify-never --ignore-not-found --wait=true >/dev/null 2>&1
  kubectl run verify-never --image=day21-app:1.0 --image-pull-policy=Never >/dev/null 2>&1 || return 1
  local ok=1
  kubectl wait --for=condition=Ready pod/verify-never --timeout=60s >/dev/null 2>&1 || ok=0
  kubectl delete pod verify-never --wait=false >/dev/null 2>&1
  [ $ok = 1 ]
}
app_pull_always_fails() { # imagePullPolicy Always asks a registry that has never heard of the image
  kubectl delete pod verify-always --ignore-not-found --wait=true >/dev/null 2>&1
  kubectl run verify-always --image=day21-app:1.0 --image-pull-policy=Always >/dev/null 2>&1 || return 1
  local i reason=""
  for i in $(seq 1 30); do
    reason=$(kubectl get pod verify-always -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
    case $reason in ErrImagePull | ImagePullBackOff) break ;; esac
    sleep 2
  done
  kubectl delete pod verify-always --wait=false >/dev/null 2>&1
  case $reason in ErrImagePull | ImagePullBackOff) return 0 ;; *) return 1 ;; esac
}
demo_sets_gone() { [ -z "$(kubectl get statefulset,pod --no-headers 2>/dev/null | grep -E 'ordered|nopassword|mariadb-env|pull-')" ]; }
sticky_name_after_delete() {
  local uid_before uid_after
  uid_before=$(jp pod/mariadb-statefulset-0 '{.metadata.uid}')
  kubectl delete pod mariadb-statefulset-0 --wait=true >/dev/null || return 1
  wait_for "pod back" 180 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s || return 1
  uid_after=$(jp pod/mariadb-statefulset-0 '{.metadata.uid}')
  [ "$uid_before" != "$uid_after" ]
}
db_after_replace() { wait_for "database" 120 db_login; }

step "Day 21 verification"
echo "StatefulSet"
check "mariadb-statefulset has 1 ready pod" sts_ready
check "the pod is named mariadb-statefulset-0 (sticky identity)" pod_name_sticky
check "a replaced pod is a new pod with the same name" sticky_name_after_delete
check "the database accepts the Secret's user after replacement" db_after_replace
echo "Secrets and environment variables"
check "the Secret exists and holds the user 'admin'" secret_exists
check "the Secret's values are only Base64: decoding gives the password" secret_is_base64_only
check "the StatefulSet refers to the Secret, it contains no password" uses_secret_ref
check "no plain-text password in the StatefulSet's YAML" no_plaintext_password
echo "Own image and imagePullPolicy"
check "the node has the image day21-app:1.0" node_has_app_image
check "day21-app has 2 ready pods" app_ready
check "the app reports the plain variable and the Secret's user and password length" app_answers
check "the app never prints the password" app_never_shows_password
check "imagePullPolicy: Never starts a pod from the node's copy" app_pull_never_ok
check "imagePullPolicy: Always fails, the image is on no registry" app_pull_always_fails
check "the \"mariadb:latest\" pod sets imagePullPolicy: IfNotPresent" pull_policy_set
echo "clean-up"
check "the demo StatefulSets and pull-policy pods are gone" demo_sets_gone
summary

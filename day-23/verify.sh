#!/usr/bin/env bash
# Day 23 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_cluster
K8S_NAMESPACE=day23

# contains <text>: reads all of stdin, then looks for the text. (grep -q stops reading early, so the
# program feeding it, curl, can die of SIGPIPE and "pipefail" would report a failure for a match.)
contains() { local data; data=$(cat); [[ $data == *"$1"* ]]; }
jp() { kubectl get "$1" -o jsonpath="$2"; }
cluster_jp() { command kubectl --context "$CTX" get "$1" -o jsonpath="$2"; }
node() { docker exec "$NODE" "$@"; }
sql() { kubectl exec mariadb-statefulset-0 -- sh -c "mariadb -u\"\$MARIADB_USER\" -p\"\$MARIADB_PASSWORD\" wordpress -N -e \"$1\""; }
db_ready() { sql 'select 1' >/dev/null 2>&1; }
site_title() { curl -s -L -m 10 http://localhost:30082 | grep -o '<title>[^<]*' | head -1 | sed 's/<title>//'; }

default_class() { [ "$(cluster_jp storageclass/standard '{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ]; }
hostpath_class() { [ "$(cluster_jp storageclass/hostpath '{.provisioner}')" = "kubernetes.io/no-provisioner" ]; }
pv_bound() { [ "$(cluster_jp pv/day23-local-pv '{.status.phase}')" = "Bound" ] && [ "$(cluster_jp pv/day23-local-pv '{.spec.claimRef.name}')" = "local-pvc" ]; }
pvc_bound() { [ "$(jp "pvc/$1" '{.status.phase}')" = "Bound" ]; }
pv_file() { [ "$(node cat /mnt/day23-pv/note.txt)" = "written to a PersistentVolume" ]; }
hostpath_file() { [ "$(node cat /mnt/day23-hostpath/note.txt)" = "written to a hostPath volume" ]; }
pv_survives_new_pod() { # a brand new pod that mounts the claim sees the file written before
  kubectl delete pod verify-pvc --ignore-not-found --wait=true >/dev/null 2>&1
  sed 's/name: pvc-pod/name: verify-pvc/' pvc-pod.yaml | kubectl apply -f - >/dev/null || return 1
  local ok=1
  kubectl wait --for=condition=Ready pod/verify-pvc --timeout=90s >/dev/null 2>&1 || ok=0
  [ $ok = 1 ] && [ "$(kubectl exec verify-pvc -- cat /data/note.txt)" = "written to a PersistentVolume" ] || ok=0
  kubectl delete pod verify-pvc --wait=false >/dev/null 2>&1
  [ $ok = 1 ]
}
second_claim_cannot_bind() { # a PV can only be used by a single claim (slide 485)
  kubectl delete pvc verify-second --ignore-not-found >/dev/null 2>&1
  kubectl apply -f - >/dev/null <<'YAML' || return 1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: verify-second
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
  storageClassName: hostpath
YAML
  kubectl run verify-second-pod --image=ubuntu --restart=Never --overrides='{"spec":{"containers":[{"name":"c","image":"ubuntu","command":["sleep","60"],"volumeMounts":[{"mountPath":"/d","name":"v"}]}],"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"verify-second"}}]}}' >/dev/null 2>&1
  sleep 8
  local phase
  phase=$(jp pvc/verify-second '{.status.phase}')
  kubectl delete pod verify-second-pod --wait=false >/dev/null 2>&1
  kubectl delete pvc verify-second --wait=false >/dev/null 2>&1
  [ "$phase" = "Pending" ]
}
rwx_not_provisioned() { ! kubectl get pvc pvc-rwx >/dev/null 2>&1; }
no_demo_pods() { [ -z "$(kubectl get pods --no-headers 2>/dev/null | grep -E 'emptydir|hostpath-pod|pvc-pending|rwx')" ]; } # pvc-pod stays: it is the user of local-pvc
db_pvc_template() { [ "$(jp pvc/mariadb-data-mariadb-statefulset-0 '{.spec.storageClassName}')" = "standard" ]; }
db_ready_one() { [ "$(jp statefulset/mariadb-statefulset '{.status.readyReplicas}')" = "1" ]; }
db_row() { [ "$(sql 'select text from notes')" = "this survives pod replacement" ]; }
db_survives_pod_delete() {
  kubectl delete pod mariadb-statefulset-0 --wait=true >/dev/null || return 1
  wait_for "database pod" 240 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s || return 1
  wait_for "database" 120 db_ready || return 1
  db_row
}
wp_ready() { [ "$(jp deployment/wordpress-deployment '{.status.readyReplicas}')" = "2" ]; }
wp_installed() { [ "$(site_title)" = "Day 23 WordPress" ]; }
wp_already_installed() { curl -s -L -m 10 'http://localhost:30082/wp-admin/install.php' | contains 'Already Installed'; }
wp_same_files() {
  local sums
  sums=$(for pod in $(kubectl get pods -l app=wordpress -o jsonpath='{.items[*].metadata.name}'); do kubectl exec "$pod" -- md5sum /var/www/html/wp-config.php | cut -d' ' -f1; done | sort -u | wc -l)
  [ "$sums" = "1" ]
}
wp_survives_everything() {
  kubectl delete pod -l app=wordpress --wait=false >/dev/null || return 1
  kubectl delete pod mariadb-statefulset-0 --wait=false >/dev/null || return 1
  wait_for "database pod" 240 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s || return 1
  wait_for "2 WordPress pods" 240 wp_ready || return 1
  wait_for "the installed site" 120 wp_installed
}
nodeport_from_network() { curl -s -L -m 10 "http://$(tailscale ip -4 | head -1):30082" | contains 'Day 23 WordPress'; }

step "Day 23 verification"
echo "volume types"
check "hostPath: the file written by a deleted pod is on the node" hostpath_file
check "the default StorageClass 'standard' exists" default_class
check "the StorageClass 'hostpath' for manually created volumes exists" hostpath_class
echo "PersistentVolume and claim"
check "the PersistentVolume is Bound to the claim local-pvc" pv_bound
check "the claim local-pvc is Bound" pvc_bound local-pvc
check "the file written through the claim is in the volume's directory on the node" pv_file
check "a brand new pod mounting the claim sees the file" pv_survives_new_pod
check "a second claim cannot bind to the volume (one volume, one claim)" second_claim_cannot_bind
check "the ReadWriteMany claim was removed again" rwx_not_provisioned
check "the demo pods were removed (pvc-pod stays, it uses local-pvc)" no_demo_pods
echo "StatefulSet with volumeClaimTemplates"
check "MariaDB StatefulSet has 1 ready pod" db_ready_one
check "the claim mariadb-data-mariadb-statefulset-0 exists and is Bound" pvc_bound mariadb-data-mariadb-statefulset-0
check "the claim comes from the template, class 'standard'" db_pvc_template
check "the row written before the StatefulSet was deleted and re-created is still there" db_row
check "deleting the database pod loses no data" db_survives_pod_delete
echo "WordPress"
check "WordPress has 2 ready replicas" wp_ready
check "the claim wordpress-data is Bound" pvc_bound wordpress-data
check "the site is installed: it shows the title 'Day 23 WordPress'" wp_installed
check "the installer says 'Already Installed'" wp_already_installed
check "both replicas see the same wp-config.php (one shared volume)" wp_same_files
check "the site is reachable on the server's Tailscale address, port 30082" nodeport_from_network
check "deleting all WordPress pods and the database pod loses nothing" wp_survives_everything
summary

#!/usr/bin/env bash
# Day 25 checks. Run after lab.sh (which needs the day 24 cluster).
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-24/env.sh
need_docker
need_k8s_tools
need_cluster

get() { curl -s -m 8 "$@"; }
# contains PATTERN command...: run the command to completion first, then search its output.
# (Piping straight into `grep -q` can make curl fail with a broken pipe under pipefail.)
contains() {
  local pattern=$1 out
  shift
  out=$("$@" 2>/dev/null)
  grep -qi -- "$pattern" <<<"$out"
}
zone_of_pod() {
  kc get node "$(kc get pod "$1" -o jsonpath='{.spec.nodeName}')" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'
  echo
}
wp_pods() { kc get pods -l app=wordpress -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'; }

efs_class() { [ "$(kc get storageclass efs -o jsonpath='{.provisioner}')" = "cluster.local/efs-nfs-server-provisioner" ]; }
provisioner_ready() { [ "$(kc -n efs get statefulset efs-nfs-server-provisioner -o jsonpath='{.status.readyReplicas}')" = "1" ]; }
standard_default() { [ "$(kc get storageclass standard -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ]; }
wp_pvc_rwx() { [ "$(kc get pvc wp-content -o jsonpath='{.status.phase}:{.status.accessModes[0]}:{.spec.storageClassName}')" = "Bound:ReadWriteMany:efs" ]; }
db_pvc_rwo() { [ "$(kc get pvc data-mysql-0 -o jsonpath='{.status.phase}:{.status.accessModes[0]}:{.spec.storageClassName}')" = "Bound:ReadWriteOnce:standard" ]; }
db_ready() { [ "$(kc get statefulset mysql -o jsonpath='{.status.readyReplicas}')" = "1" ]; }
db_in_zone_a() { [ "$(zone_of_pod mysql-0)" = "eu-west-3a" ]; }
db_volume_node_bound() {
  local pv
  pv=$(kc get pvc data-mysql-0 -o jsonpath='{.spec.volumeName}')
  kc get pv "$pv" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].key}' | grep -q hostname
}
wp_ready() { [ "$(kc get deployment wordpress -o jsonpath='{.status.readyReplicas}')" = "2" ]; }
wp_two_zones() { [ "$(for p in $(wp_pods); do zone_of_pod "$p"; done | sort -u | wc -l)" = "2" ]; }
shared_files() {
  local a b token
  a=$(wp_pods | sed -n 1p)
  b=$(wp_pods | sed -n 2p)
  token="verify-$RANDOM-$RANDOM"
  kc exec "$a" -- sh -c "echo $token > /var/www/html/wp-content/verify-token.txt" || return 1
  [ "$(kc exec "$b" -- cat /var/www/html/wp-content/verify-token.txt)" = "$token" ]
  local rc=$?
  kc exec "$a" -- rm -f /var/www/html/wp-content/verify-token.txt
  return $rc
}
wp_reaches_db() { ! contains 'Error establishing a database connection' get -L http://localhost:8450/wp-admin/install.php; }
wp_install_page() { [ "$(curl -s -m 8 -L -o /dev/null -w '%{http_code}' http://localhost:8450/)" = "200" ]; }
wp_install_title() { contains '<title>WordPress &rsaquo; Installation</title>' get -L http://localhost:8450/wp-admin/install.php; }
marker_present() {
  local pass
  pass=$(kc get secret mysql -o jsonpath='{.data.root-password}' | base64 -d)
  [ "$(kc exec mysql-0 -- mysql -uroot "-p$pass" -N -B -e 'SELECT note FROM wordpress.marker WHERE id = 1' 2>/dev/null)" = "survives pod deletion" ]
}
zone_demo_pending() {
  kc delete pod zone-demo --ignore-not-found --wait=true >/dev/null
  kc apply -f zone-demo.yaml >/dev/null
  sleep 8
  local phase msg
  phase=$(kc get pod zone-demo -o jsonpath='{.status.phase}')
  msg=$(kc get events --field-selector involvedObject.name=zone-demo,reason=FailedScheduling -o jsonpath='{.items[-1].message}')
  kc delete pod zone-demo --wait=false >/dev/null
  [ "$phase" = "Pending" ] && echo "$msg" | grep -q "didn't match PersistentVolume's node affinity"
}
teardown_exists() { [ -x teardown.sh ] && bash -n teardown.sh; }

step "Day 25 verification"
echo "shared filesystem (EFS stand-in, slide 537)"
check "StorageClass efs is served by the NFS provisioner" efs_class
check "the NFS provisioner is ready" provisioner_ready
check "claim wp-content is Bound, ReadWriteMany, class efs" wp_pvc_rwx
echo "block storage (EBS stand-in, slides 539, 548)"
check "StorageClass standard is the default" standard_default
check "claim data-mysql-0 is Bound, ReadWriteOnce, class standard" db_pvc_rwo
check "its volume is bound to one node (nodeAffinity on hostname)" db_volume_node_bound
echo "MySQL"
check "the MySQL StatefulSet is ready" db_ready
check "mysql-0 runs in zone eu-west-3a (slide 544)" db_in_zone_a
check "a row written before the pod was deleted is still there" marker_present
echo "WordPress"
check "the WordPress Deployment has 2 ready pods" wp_ready
check "the 2 pods run in 2 different zones" wp_two_zones
check "a file written by one pod is read by the other (ReadWriteMany)" shared_files
check "http://localhost:8450 ends on a 200 page" wp_install_page
check "WordPress reaches MySQL (no database connection error)" wp_reaches_db
check "the page is WordPress' install screen" wp_install_title
echo "zones (slides 542-546)"
check "a pod claiming the database volume from the other zone stays Pending" zone_demo_pending
echo "teardown (slide 550)"
check "teardown.sh exists and is valid bash" teardown_exists
summary

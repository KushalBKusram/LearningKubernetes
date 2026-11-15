#!/usr/bin/env bash
# Day 25 lab: EKS storage, availability zones and teardown (slides 534-550).
# Runs on the server, on the "eks" cluster of day 24 (lab.sh of day 24 must have run).
# Safe to run more than once.
#
# Leaves running:
#   8450   WordPress (NodePort 30081), two pods in two zones, files on the shared "efs" volume
#   MySQL  StatefulSet in eu-west-3a, data on a ReadWriteOnce volume
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-24/env.sh
need_docker
need_k8s_tools
need_cluster

NFS_CHART_VERSION=1.8.0
body() { curl -s -m 8 "$@" || true; }

step "1. The shared filesystem: EFS becomes an NFS server in the cluster (slide 537)"
echo "On EKS: create the EFS volume in the cluster's VPC, open it to the nodes' security group, install the EFS driver."
echo "Here: one Helm chart runs an NFS server in the cluster and a provisioner that carves out a folder per claim."
helm repo add nfs-ganesha https://kubernetes-sigs.github.io/nfs-ganesha-server-and-external-provisioner/ --force-update >/dev/null
run helm --kube-context "$EKS_CONTEXT" upgrade --install efs nfs-ganesha/nfs-server-provisioner \
  --version "$NFS_CHART_VERSION" --namespace efs --create-namespace \
  --set storageClass.name=efs \
  --set persistence.enabled=true --set persistence.storageClass=standard --set persistence.size=2Gi \
  --wait --timeout 300s
run kubectl --context "$EKS_CONTEXT" get storageclass

step "2. The block storage: EBS becomes the default StorageClass (slides 539, 548)"
echo "The EBS driver of EKS is the stand-in's 'standard' class: local-path volumes are ReadWriteOnce and sit on one node."
run kubectl --context "$EKS_CONTEXT" get storageclass standard -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner,BINDING:.volumeBindingMode,DEFAULT:'.metadata.annotations.storageclass\.kubernetes\.io/is-default-class'

step "3. MySQL on the block volume, pinned to one zone (slides 540, 544)"
load_image mysql:8.4
run kubectl --context "$EKS_CONTEXT" apply -f mysql.yaml
run kubectl --context "$EKS_CONTEXT" rollout status statefulset/mysql --timeout=300s
run kubectl --context "$EKS_CONTEXT" get pod mysql-0 -o wide
run kubectl --context "$EKS_CONTEXT" get pvc data-mysql-0

step "4. WordPress on the shared volume (slides 499, 537)"
load_image wordpress:latest
run kubectl --context "$EKS_CONTEXT" apply -f wordpress.yaml
run kubectl --context "$EKS_CONTEXT" rollout status deployment/wordpress --timeout=300s
run kubectl --context "$EKS_CONTEXT" get pods -l app=wordpress -o wide
run kubectl --context "$EKS_CONTEXT" get pvc wp-content
name=$(server_name)
wait_http "http://localhost:8450/wp-admin/install.php" 200 -L || true
echo "http://$name:8450/ -> $(curl -s -m 8 -L -o /dev/null -w '%{http_code}, ended at %{url_effective}' http://localhost:8450/)"

step "5. Both zones see the same files: ReadWriteMany (slide 537)"
mapfile -t wp < <(kc get pods -l app=wordpress -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
for p in "${wp[@]}"; do
  echo "$p runs in zone $(kc get node "$(kc get pod "$p" -o jsonpath='{.spec.nodeName}')" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')"
done
stamp="written by ${wp[0]} at $(date +%T)"
run kubectl --context "$EKS_CONTEXT" exec "${wp[0]}" -- sh -c "echo '$stamp' > /var/www/html/wp-content/shared.txt"
echo "Read from the other pod: $(kc exec "${wp[1]}" -- cat /var/www/html/wp-content/shared.txt)"

step "6. Data on the block volume outlives its pod (slide 539)"
pass=$(kc get secret mysql -o jsonpath='{.data.root-password}' | base64 -d)
sql() { kc exec mysql-0 -- mysql -uroot "-p$pass" -N -B -e "$1" 2>/dev/null; }
sql "CREATE TABLE IF NOT EXISTS wordpress.marker (id INT PRIMARY KEY, note VARCHAR(80)); REPLACE INTO wordpress.marker VALUES (1, 'survives pod deletion');"
echo "Before: $(sql 'SELECT note FROM wordpress.marker WHERE id = 1')"
node_before=$(kc get pod mysql-0 -o jsonpath='{.spec.nodeName}')
run kubectl --context "$EKS_CONTEXT" delete pod mysql-0 --wait
run kubectl --context "$EKS_CONTEXT" rollout status statefulset/mysql --timeout=300s
for _ in $(seq 1 30); do [ -n "$(sql 'SELECT note FROM wordpress.marker WHERE id = 1')" ] && break; sleep 2; done
echo "After:  $(sql 'SELECT note FROM wordpress.marker WHERE id = 1')"
echo "The new pod runs on $(kc get pod mysql-0 -o jsonpath='{.spec.nodeName}') (before: $node_before): the volume brought it back to the same node."

step "7. A zone-bound volume pins its pod (slides 542-546)"
pv=$(kc get pvc data-mysql-0 -o jsonpath='{.spec.volumeName}')
echo "The volume $pv may only be used on:"
kc get pv "$pv" -o jsonpath='{range .spec.nodeAffinity.required.nodeSelectorTerms[*].matchExpressions[*]}  {.key} in {.values}{"\n"}{end}'
echo "(EBS pins by availability zone; local-path pins by node. The node is in $(kc get node "$node_before" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}').)"
echo
echo "Now a pod that claims this volume but must run in the other zone (eu-west-3b):"
kc delete pod zone-demo --ignore-not-found >/dev/null
run kubectl --context "$EKS_CONTEXT" apply -f zone-demo.yaml
sleep 8
run kubectl --context "$EKS_CONTEXT" get pod zone-demo
kc get events --field-selector involvedObject.name=zone-demo,reason=FailedScheduling -o jsonpath='{.items[-1].message}{"\n"}' | sed 's/^/  scheduler: /'
run kubectl --context "$EKS_CONTEXT" delete pod zone-demo --wait=false
echo
echo "Slide 543 warns that automatic provisioning picks one zone for the volume; if the pod is later rescheduled"
echo "into the other zone, it cannot reach its data. Slide 544's answer is what mysql.yaml does: pin the pods that need the volume."

step "Done"
echo "WordPress: http://$name:8450  (install screen; no account is created)"
echo "Next: setup/run.sh day-25/verify.sh. When you are finished with the cluster: setup/run.sh day-25/teardown.sh"

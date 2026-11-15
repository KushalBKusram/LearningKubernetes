#!/usr/bin/env bash
# Day 23 lab: storage in Kubernetes (slides 468-497).
# Runs on the server, in the namespace day23 of the cluster from day 19.
# Safe to run more than once: it starts by emptying its own namespace and its own cluster-wide objects.
#
# Leaves running: MariaDB with a volume (StatefulSet), WordPress x2 sharing a volume, on port 30082.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_cluster
ensure_cluster_healthy
use_namespace day23

node() { docker exec "$NODE" "$@"; }
pod_ready() { wait_for "$1 to be ready" "${2:-180}" kubectl wait --for=condition=Ready "pod/$1" --timeout=5s; }
sql() { kubectl exec mariadb-statefulset-0 -- sh -c "mariadb -u\"\$MARIADB_USER\" -p\"\$MARIADB_PASSWORD\" wordpress -N -e \"$1\""; }
db_ready() { sql 'select 1' >/dev/null 2>&1; }
site_title() { curl -s -L -m 10 http://localhost:30082 | grep -o '<title>[^<]*' | head -1 | sed 's/<title>//'; }
wp_ready() { [ "$(kubectl get deployment wordpress-deployment -o jsonpath='{.status.readyReplicas}')" = "$1" ]; }
has_event() { kubectl get events --field-selector "involvedObject.name=$1" -o jsonpath='{.items[*].message}' | grep -qi "$2"; }
title_is() { [ "$(site_title)" = "$1" ]; }

step "0. Start clean, and give the node the images it needs"
kubectl delete deployment,statefulset,service,pod --all --wait=true >/dev/null 2>&1 || true
kubectl delete pvc --all --wait=true >/dev/null 2>&1 || true
kubectl delete secret my-mariadb-secret --ignore-not-found >/dev/null
command kubectl --context "$CTX" delete pv day23-local-pv --ignore-not-found >/dev/null
command kubectl --context "$CTX" delete storageclass hostpath --ignore-not-found >/dev/null
node rm -rf /mnt/day23-hostpath /mnt/day23-pv
for image in ubuntu mariadb:latest wordpress:latest; do preload_image "$image"; done

step "1. Kubernetes volumes are not Docker volumes (slide 473)"
echo "The volumes below are managed by Kubernetes and described in YAML. Docker's own volumes (day 13) are a separate"
echo "thing that Kubernetes knows nothing about, and never manages for us."

step "2. Ephemeral volume: emptyDir (slides 472, 475)"
run kubectl apply -f emptydir-pod.yaml
pod_ready emptydir-pod
run kubectl exec emptydir-pod -- sh -c 'echo "written to the emptyDir" > /app/note.txt && cat /app/note.txt'
echo "Delete the pod and create it again from the same file:"
run kubectl delete pod emptydir-pod
run kubectl apply -f emptydir-pod.yaml
pod_ready emptydir-pod
echo "Files in /app now: '$(kubectl exec emptydir-pod -- ls /app)' (none). The volume lived exactly as long as the first pod."
kubectl delete pod emptydir-pod --wait=true >/dev/null

step "3. hostPath: a directory of the node (slide 477)"
run kubectl apply -f hostpath-pod.yaml
pod_ready hostpath-pod
run kubectl exec hostpath-pod -- sh -c 'echo "written to a hostPath volume" > /app/note.txt'
echo "The file is in the node's own filesystem (the node is the Docker container $NODE):"
run docker exec "$NODE" cat /mnt/day23-hostpath/note.txt
echo "Delete the pod and create it again:"
run kubectl delete pod hostpath-pod
run kubectl apply -f hostpath-pod.yaml
pod_ready hostpath-pod
echo "Files in /app now: '$(kubectl exec hostpath-pod -- ls /app)'. The data survived, but it belongs to this one node."
echo "A pod rescheduled to another node would not find it (slide 477), so hostPath is mostly for temporary or node-specific data."
kubectl delete pod hostpath-pod --wait=true >/dev/null

step "4. StorageClass (slide 480)"
echo "The cluster already has one, the default:"
run kubectl get storageclass
echo "The provisioner (rancher.io/local-path) is the 'driver': it creates a directory on the node for every claim."
echo "The slides' class 'hostpath' belongs to Docker Desktop. Create an equivalent for manually made volumes:"
run cat storageclass.yaml
run kubectl apply -f storageclass.yaml
run kubectl get storageclass

step "5. PersistentVolume: a place to store data (slides 482-483)"
run kubectl apply -f pv.yaml
run kubectl get pv day23-local-pv

step "6. PersistentVolumeClaim: a request for storage (slides 485, 487)"
run kubectl apply -f pvc.yaml
sleep 2
run kubectl get pvc local-pvc
echo "It is Pending, not Bound: the class says WaitForFirstConsumer, so the claim binds when a pod first uses it."

step "7. A pod that uses the claim (slide 489)"
run kubectl apply -f pvc-pod.yaml
pod_ready pvc-pod
run kubectl get pvc,pv
run kubectl exec pvc-pod -- sh -c 'echo "written to a PersistentVolume" > /data/note.txt'
echo "Delete the pod and create it again. It mounts the same claim:"
run kubectl delete pod pvc-pod
run kubectl apply -f pvc-pod.yaml
pod_ready pvc-pod
run kubectl exec pvc-pod -- cat /data/note.txt
echo "The data is stored where the PersistentVolume says, here /mnt/day23-pv on the node:"
run docker exec "$NODE" cat /mnt/day23-pv/note.txt

step "8. Which claims fit which volume (slide 486)"
grep -E '^  name:|storageClassName' pvc-unmatched.yaml | sed 's/^/  | /'
run kubectl apply -f pvc-unmatched.yaml
sleep 8
run kubectl get pvc
run kubectl get pod pvc-pending-pod
echo
echo "pvc-wrong-class asks for a class no volume has. pvc-second asks for 'hostpath', but the only volume of that class is taken:"
echo "a PersistentVolume can only be used by a single claim (slide 485). The pod that uses them cannot start either:"
kubectl get events --field-selector involvedObject.name=pvc-pending-pod -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' | sort -u | head -2 | sed 's/^/  /'
kubectl delete -f pvc-unmatched.yaml --wait=true >/dev/null

step "9. Access modes (slides 493-494)"
run kubectl get pv day23-local-pv -o custom-columns=NAME:.metadata.name,ACCESS:.spec.accessModes,CLASS:.spec.storageClassName
echo "ReadWriteOnce: one node at a time. ReadWriteMany: many nodes at once (shared storage such as EFS on AWS)."
echo "This cluster's default storage cannot do ReadWriteMany. A claim asking for it:"
run kubectl apply -f rwx.yaml
wait_for "the provisioning error" 90 has_event pvc-rwx ReadWriteOnce
run kubectl get pvc pvc-rwx
echo "The reason, from the claim's events:"
kubectl get events --field-selector involvedObject.name=pvc-rwx -o jsonpath='{range .items[*]}{.reason}: {.message}{"\n"}{end}' | grep -i 'ReadWriteOnce' | head -1 | cut -c1-200 | sed 's/^/  /'
kubectl delete -f rwx.yaml --wait=true >/dev/null
echo "(EFS can be shared by pods on many nodes, EBS only by one node at a time: slide 494, and day 25.)"

step "10. A claim per pod: volumeClaimTemplates in a StatefulSet (slide 491)"
run kubectl apply -f secret.yaml
run kubectl apply -f mariadb.yaml
pod_ready mariadb-statefulset-0 240
wait_for "the database" 120 db_ready
run kubectl get pvc
echo "The StatefulSet created the claim itself, named <template>-<pod>: mariadb-data-mariadb-statefulset-0."
run kubectl exec mariadb-statefulset-0 -- sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" wordpress -e "create table notes (text varchar(60)); insert into notes values (\"this survives pod replacement\"); select * from notes"'
echo "On day 21 deleting the database pod lost the data. Now:"
run kubectl delete pod mariadb-statefulset-0
pod_ready mariadb-statefulset-0 240
wait_for "the database" 120 db_ready
echo "Rows after the pod was replaced: $(sql 'select text from notes')"
echo
echo "Even deleting the StatefulSet keeps the claim and its data (a safety feature):"
run kubectl delete statefulset mariadb-statefulset
run kubectl get pvc mariadb-data-mariadb-statefulset-0
run kubectl apply -f mariadb.yaml
pod_ready mariadb-statefulset-0 240
wait_for "the database" 120 db_ready
echo "Rows after deleting and re-creating the whole StatefulSet: $(sql 'select text from notes')"

step "11. WordPress, finally installed, and its data kept (slide 469)"
run kubectl apply -f wordpress.yaml
run kubectl rollout status deployment/wordpress-deployment --timeout=240s
wait_for "WordPress on port 30082" 90 curl -s -m 5 -o /dev/null http://localhost:30082
echo "The installer page, from the server: $(site_title)"
admin_password=$(kubectl get secret my-mariadb-secret -o jsonpath='{.data.password}' | base64 -d)
echo "Run the installation (the slides do it in the browser; here the form is submitted with curl):"
echo "\$ curl -X POST 'http://localhost:30082/wp-admin/install.php?step=2' -d weblog_title='Day 23 WordPress' -d user_name=admin ..."
curl -s -m 60 -o /dev/null -X POST 'http://localhost:30082/wp-admin/install.php?step=2' \
  --data-urlencode 'weblog_title=Day 23 WordPress' --data-urlencode 'user_name=admin' \
  --data-urlencode "admin_password=$admin_password" --data-urlencode "admin_password2=$admin_password" \
  --data-urlencode 'pw_weak=1' --data-urlencode 'admin_email=admin@example.com' --data-urlencode 'blog_public=0' \
  --data-urlencode 'language=' --data-urlencode 'Submit=Install WordPress'
echo "The site now says: '$(site_title)'"
echo
echo "Add a second replica. It finds WordPress's files on the shared volume and serves the same site:"
run kubectl scale deployment/wordpress-deployment --replicas=2
run kubectl rollout status deployment/wordpress-deployment --timeout=240s
run kubectl get pods -l app=wordpress -o wide
for pod in $(kubectl get pods -l app=wordpress -o jsonpath='{.items[*].metadata.name}'); do
  echo "  $pod: wp-config.php checksum $(kubectl exec "$pod" -- md5sum /var/www/html/wp-config.php | cut -c1-12)"
done
echo "(the same file, because both pods mount the same claim)"
echo
echo "Now delete every WordPress pod and the database pod at once:"
run kubectl delete pod -l app=wordpress
run kubectl delete pod mariadb-statefulset-0
pod_ready mariadb-statefulset-0 240
wait_for "2 ready WordPress pods" 240 wp_ready 2
wait_for "the site" 120 title_is "Day 23 WordPress"
echo "The site still says: '$(site_title)'. Nothing was reinstalled: the installer would be showing otherwise."
echo "Installer page says: $(curl -s -L -m 10 'http://localhost:30082/wp-admin/install.php' | grep -o 'Already Installed' | head -1)"
run kubectl get pvc

step "Done"
echo "WordPress: http://$(public_name):30082   (admin login: user 'admin', password from secret.yaml)"
echo "Next: setup/run.sh day-23/verify.sh"

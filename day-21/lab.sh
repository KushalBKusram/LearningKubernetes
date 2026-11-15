#!/usr/bin/env bash
# Day 21 lab: StatefulSets, environment variables, Secrets, own images (slides 404-414).
# (Slides 416-441 repeat this section, so it is covered once.)
# Runs on the server, in the namespace day21 of the cluster from day 19.
# Safe to run more than once: it starts by emptying its own namespace.
#
# Leaves running: mariadb-statefulset (1 pod), day21-app (2 pods), the Secret my-mariadb-secret.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_cluster
ensure_cluster_healthy
use_namespace day21

sql() { # sql <pod> <statement>: runs it as the database user that the Secret created
  kubectl exec "$1" -- sh -c "mariadb -u\"\$MARIADB_USER\" -p\"\$MARIADB_PASSWORD\" -N -e \"$2\""
}
waiting_reason() { kubectl get pod "$1" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' | grep -qE "$2"; }
has_restarted() { kubectl get pod "$1" -o jsonpath='{.status.containerStatuses[0].restartCount}' | grep -qE '^[1-9]'; }
db_ready() { kubectl exec "$1" -- sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" -e "select 1"' >/dev/null 2>&1; }

step "0. Start clean, and give the node the images it needs"
kubectl delete statefulset,deployment,pod --all --wait=true >/dev/null 2>&1 || true
kubectl delete secret my-mariadb-secret --ignore-not-found >/dev/null
kubectl delete pvc --all >/dev/null 2>&1 || true
for image in ubuntu mariadb:latest; do preload_image "$image"; done
echo "Images on the node: $(docker exec "$NODE" crictl images 2>/dev/null | awk '/ubuntu|mariadb/ {print $1 ":" $2}' | tr '\n' ' ')"

step "1. StatefulSet: sticky names, ordered start and stop (slides 404-405)"
run kubectl apply -f statefulset-ordered.yaml
wait_for "3 ordered pods" 180 kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 statefulset/ordered --timeout=5s
run kubectl get pods -l app=ordered -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp
echo "Pods are named ordered-0, ordered-1, ordered-2 (a Deployment's pods get random names) and were created in that order,"
echo "each one only after the one before was ready."
echo
echo "Delete ordered-1. It comes back with the same name (its identity is sticky):"
uid_before=$(kubectl get pod ordered-1 -o jsonpath='{.metadata.uid}')
run kubectl delete pod ordered-1
wait_for "ordered-1 again" 120 kubectl wait --for=condition=Ready pod/ordered-1 --timeout=5s
[ "$(kubectl get pod ordered-1 -o jsonpath='{.metadata.uid}')" != "$uid_before" ] && echo "(a new pod, same name: ordered-1)"
echo
echo "Scale down to 1: the highest numbers go first, in reverse order:"
run kubectl scale statefulset/ordered --replicas=1
wait_for "scale down" 120 kubectl wait --for=jsonpath='{.status.replicas}'=1 statefulset/ordered --timeout=5s
run kubectl get pods -l app=ordered
kubectl delete statefulset ordered >/dev/null

step "2. MariaDB without configuration does not start (slide 407)"
run kubectl apply -f statefulset-no-password.yaml
wait_for "the failure" 120 has_restarted mariadb-nopassword-0
run kubectl get pod mariadb-nopassword-0
echo "The reason, from the container's log:"
kubectl logs mariadb-nopassword-0 --previous 2>&1 | grep -iE 'uninitialized|password' | head -2 | sed 's/^/  /'
kubectl delete statefulset mariadb-nopassword >/dev/null

step "3. An environment variable fixes it (slide 407)"
run kubectl apply -f statefulset-env.yaml
wait_for "mariadb-env-0" 180 kubectl wait --for=condition=Ready pod/mariadb-env-0 --timeout=5s
wait_for "the database" 120 kubectl exec mariadb-env-0 -- mariadb -uroot -ppassword -e 'select 1'
run kubectl exec mariadb-env-0 -- mariadb -uroot -ppassword -e 'select version() as version'
echo
echo "The weakness: the password is in plain text in the object, visible to anyone who can read it:"
kubectl get statefulset mariadb-env -o jsonpath='{.spec.template.spec.containers[0].env}' | sed 's/^/  /'
echo
kubectl delete statefulset mariadb-env >/dev/null

step "4. A Secret (slide 409)"
run cat secret.yaml
run kubectl apply -f secret.yaml
run kubectl get secret my-mariadb-secret
echo
echo "The values are Base64. That is an encoding, not encryption:"
echo "  username: $(kubectl get secret my-mariadb-secret -o jsonpath='{.data.username}')  ->  $(kubectl get secret my-mariadb-secret -o jsonpath='{.data.username}' | base64 -d)"
echo "  password: $(kubectl get secret my-mariadb-secret -o jsonpath='{.data.password}')  ->  $(kubectl get secret my-mariadb-secret -o jsonpath='{.data.password}' | base64 -d)"
echo
echo "A Secret can also be generated without writing the Base64 by hand (nothing is created here):"
run kubectl create secret generic example --from-literal=password=hunter2 --dry-run=client -o yaml

step "5. Using the Secret as environment variables (slide 410)"
run kubectl apply -f statefulset.yaml
wait_for "mariadb-statefulset-0" 180 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s
wait_for "the database" 120 db_ready mariadb-statefulset-0
echo "The pod's environment, from the Secret:"
echo "  MARIADB_USER=$(kubectl exec mariadb-statefulset-0 -- printenv MARIADB_USER)"
echo "  MARIADB_PASSWORD has $(kubectl exec mariadb-statefulset-0 -- printenv MARIADB_PASSWORD | tr -d '\n' | wc -c) characters"
echo "The YAML of the StatefulSet only names the Secret, it holds no password:"
kubectl get statefulset mariadb-statefulset -o jsonpath='{.spec.template.spec.containers[0].env[0]}' | sed 's/^/  /'
echo
echo
echo "Log in as the user the Secret created, and write something:"
run kubectl exec mariadb-statefulset-0 -- sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" wordpress -e "create table notes (text varchar(50)); insert into notes values (\"written before the pod is replaced\"); select * from notes"'
echo
echo "There is no storage yet. Delete the pod and the StatefulSet starts a new one with the same name, but an empty database:"
run kubectl delete pod mariadb-statefulset-0
wait_for "the pod to be replaced" 180 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s
wait_for "the database" 120 db_ready mariadb-statefulset-0
echo "Tables in the database wordpress now: '$(sql mariadb-statefulset-0 'show tables from wordpress')' (none)"
echo "Persistent storage comes on day 23."

step "6. Using our own image (slide 413)"
echo "The app is app/server.py, a few lines of Python. Build the image on the server:"
run docker build --quiet -t day21-app:1.0 app
echo
echo "The image exists in Docker, but the cluster has its own image store, so the node cannot see it yet:"
echo "  node has day21-app:1.0 before: $(node_has_image docker.io/library/day21-app:1.0 && echo yes || echo no)"
echo "On a one-node cluster the image only has to reach that node. The slides rely on Docker Desktop sharing its images."
echo "With kind, the command is 'kind load docker-image':"
if ! { printf '\033[2m$ kind load docker-image day21-app:1.0 --name %s\033[0m\n' "$CLUSTER"; kind load docker-image day21-app:1.0 --name "$CLUSTER" 2>&1 | tail -2; } || ! node_has_image docker.io/library/day21-app:1.0; then
  echo "(that failed for this image, so the lab imports it a different way)"
  docker save day21-app:1.0 | docker exec -i --privileged "$NODE" ctr --namespace=k8s.io images import --digests --snapshotter=overlayfs - >/dev/null
fi
echo "  node has day21-app:1.0 after:  $(node_has_image docker.io/library/day21-app:1.0 && echo yes || echo no)"
echo "In the cloud the cluster pulls from a private registry instead (ECR on AWS, slide 413)."

step "7. imagePullPolicy (slide 414)"
cat pull-policy.yaml | grep -E 'name: pull|image:|imagePullPolicy' | sed 's/^/  | /'
run kubectl apply -f pull-policy.yaml
echo "Waiting a little for the kubelet to act..."
wait_for "pull-always to fail" 90 waiting_reason pull-always 'ErrImagePull|ImagePullBackOff'
wait_for "pull-ifnotpresent to run" 90 kubectl wait --for=condition=Ready pod/pull-ifnotpresent --timeout=5s
wait_for "pull-never to run" 90 kubectl wait --for=condition=Ready pod/pull-never --timeout=5s
wait_for "pull-never-missing to fail" 90 waiting_reason pull-never-missing ErrImageNeverPull
run kubectl get pods
echo
echo "IfNotPresent and Never use the copy on the node. Always asks the registry, and the registry has never heard of day21-app."
echo "Never with an image the node does not have fails at once (ErrImageNeverPull)."
echo "The default is IfNotPresent, except for the tag :latest or no tag, where it is Always. That is why statefulset.yaml sets it for mariadb:latest."
kubectl delete -f pull-policy.yaml --wait=false >/dev/null

step "8. Our image, configured by a plain variable and by the Secret (slides 407, 410)"
run kubectl apply -f app-deployment.yaml
run kubectl rollout status deployment/day21-app --timeout=180s
pod=$(kubectl get pods -l app=day21-app -o jsonpath='{.items[0].metadata.name}')
echo "What the app inside $pod reports (it prints the password's length, never the password):"
kubectl exec "$pod" -- python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000').read().decode())"

step "Done"
echo "Running in the namespace day21: mariadb-statefulset-0, 2 x day21-app, the Secret my-mariadb-secret."
echo "Next: setup/run.sh day-21/verify.sh"

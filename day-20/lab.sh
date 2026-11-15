#!/usr/bin/env bash
# Day 20 lab: pods in YAML, workloads, Deployments, labels (slides 385-403).
# Runs on the server, in the namespace day20 of the cluster from day 19.
# Safe to run more than once: it starts by emptying its own namespace.
#
# Leaves running: wordpress-deployment with 3 replicas (no database yet; that is day 21).
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_cluster
ensure_cluster_healthy
use_namespace day20

# The first line of the HTTP answer from inside a pod. The WordPress image has no curl,
# so the request is written by hand with bash and the shell's /dev/tcp.
http_line() {
  kubectl exec "$1" -- bash -c 'exec 3<>/dev/tcp/127.0.0.1/80; printf "GET / HTTP/1.0\r\n\r\n" >&3; head -n1 <&3' | tr -d '\r'
}
pods_of() { kubectl get pods -l "$1" --no-headers -o custom-columns=NAME:.metadata.name; }

step "0. Start clean, and give the node the images it needs"
kubectl delete deployment,replicaset,daemonset,job,pod --all --wait=true >/dev/null 2>&1 || true
# The node has its own image store, separate from Docker's. Copy images in when Docker
# already has them, which saves downloads from Docker Hub.
for image in ubuntu wordpress:latest; do preload_image "$image"; done
echo "Images on the node: $(docker exec "$NODE" crictl images 2>/dev/null | awk '/ubuntu|wordpress/ {print $1 ":" $2}' | tr '\n' ' ')"

step "1. A pod as YAML (slides 386-387)"
cat pod.yaml | sed -n '1,/^spec:/p' | sed '$d' | grep -v '^#' | sed 's/^/  | /'
run kubectl apply -f pod.yaml
wait_for "the pod" 120 kubectl wait --for=condition=Ready pod/day20-pod --timeout=5s
run kubectl get pod day20-pod
echo
echo "'status' is not in our file. The cluster adds it:"
kubectl get pod day20-pod -o yaml | sed -n '/^status:/,/^  containerStatuses:/p' | sed '$d' | sed 's/^/  | /'
echo "  | ... (also: containerStatuses, hostIP, podIP, phase, startTime)"
run kubectl delete pod day20-pod

step "2. Workload types (slide 391)"
echo "Job: a task that runs a set number of times, then is finished"
run kubectl apply -f job.yaml
wait_for "the job" 120 kubectl wait --for=condition=Complete job/day20-job --timeout=5s
run kubectl get job day20-job
echo
echo "DaemonSet: one pod on every node"
run kubectl apply -f daemonset.yaml
wait_for "the daemonset" 120 kubectl rollout status daemonset/day20-daemonset --timeout=5s
run kubectl get daemonset day20-daemonset
kubectl delete job/day20-job daemonset/day20-daemonset >/dev/null

step "3. ReplicaSet: keeps N copies of a pod running (slide 393)"
run kubectl apply -f replicaset.yaml
wait_for "the replicaset" 120 kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 replicaset/day20-replicaset --timeout=5s
run kubectl get replicaset,pods -l app=day20-rs
victim=$(pods_of app=day20-rs | head -1)
echo
echo "Delete one pod ($victim). The ReplicaSet notices and creates a replacement:"
run kubectl delete pod "$victim"
wait_for "3 ready pods again" 120 kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 replicaset/day20-replicaset --timeout=5s
run kubectl get pods -l app=day20-rs
echo "A ReplicaSet cannot move its pods to a new version. That is what a Deployment adds."
kubectl delete replicaset day20-replicaset --wait=true >/dev/null

step "4. Deployment: WordPress with 3 replicas (slides 395, 398)"
run kubectl apply -f deployment.yaml
run kubectl rollout status deployment/wordpress-deployment --timeout=180s
run kubectl get deployment,replicaset,pods
echo
echo "Deployment -> ReplicaSet -> Pods (slide 394). The ReplicaSet's name is the Deployment's name plus a hash of the pod template,"
echo "and each pod's name adds a random suffix: the pods are interchangeable (slide 404)."

step "5. Reaching WordPress (slide 396)"
pod=$(pods_of app=wordpress | head -1)
echo "From inside the pod $pod:"
echo "  $(http_line "$pod")"
echo "WordPress answers, but it has no database yet, so it cannot show a site. That is the next day's work."
echo
echo "The slides then reach it from outside with a port-forward. It is for development only (slide 396)."
echo "Here it runs for a few seconds on port 8600 and is stopped again:"
# "command kubectl" starts the real program, so $! is its own process id. Putting the
# kubectl wrapper function in the background would give the id of a subshell instead,
# and killing that would leave the port-forward running.
command kubectl --context "$CTX" --namespace "$K8S_NAMESPACE" port-forward deployment/wordpress-deployment 8600:80 --address 127.0.0.1 >/dev/null 2>&1 &
forward=$!
trap 'kill $forward 2>/dev/null || true' EXIT
wait_for "the port-forward" 30 curl -s -m 2 -o /dev/null http://127.0.0.1:8600
echo "\$ kubectl port-forward deployment/wordpress-deployment 8600:80"
echo "  http://127.0.0.1:8600 -> $(curl -s -m 5 -o /dev/null -w 'HTTP %{http_code}' http://127.0.0.1:8600)"
kill "$forward" 2>/dev/null || true
trap - EXIT

step "6. Labels (slide 400)"
run kubectl get deployments -l app=wordpress
run kubectl get deployments -l app=wordpress,version=1.0
echo "Labels are free-form. A label that does not match finds nothing:"
run kubectl get deployments -l app=wordpress,version=2.0
echo
echo "Show the labels as columns:"
run kubectl get deployments --show-labels

step "7. Labels for the pods and the selector (slide 402)"
run kubectl get pods -l app=wordpress --show-labels
echo
echo "spec.selector.matchLabels is immutable. Trying to change it:"
sed 's/app: wordpress # how the Deployment finds.*/app: wordpress-v2/' deployment.yaml >.selector-test.yaml
if out=$(kubectl apply -f .selector-test.yaml 2>&1); then
  echo "  UNEXPECTED: the change was accepted"
else
  echo "$out" | grep -i 'immutable' | head -1 | sed 's/^/  /'
fi
rm -f .selector-test.yaml

step "8. Scaling: pods are interchangeable, names are random (slides 395, 404)"
run kubectl scale deployment/wordpress-deployment --replicas=5
run kubectl rollout status deployment/wordpress-deployment --timeout=180s
run kubectl get pods -l app=wordpress
echo "Scaling down: Kubernetes picks which pods to end (slide 404)."
run kubectl scale deployment/wordpress-deployment --replicas=3
wait_for "3 pods" 120 kubectl wait --for=jsonpath='{.status.replicas}'=3 deployment/wordpress-deployment --timeout=5s
run kubectl get pods -l app=wordpress

step "9. Rolling update: a Deployment moves to a new ReplicaSet (slide 393)"
echo "Changing anything in the pod template creates a new ReplicaSet. Here: an environment variable."
run kubectl set env deployment/wordpress-deployment APP_VERSION=2
run kubectl rollout status deployment/wordpress-deployment --timeout=180s
run kubectl get replicaset -l app=wordpress
echo "The old ReplicaSet is kept at 0 pods, so the update can be undone:"
run kubectl rollout history deployment/wordpress-deployment
run kubectl rollout undo deployment/wordpress-deployment
run kubectl rollout status deployment/wordpress-deployment --timeout=180s
run kubectl get replicaset -l app=wordpress

step "10. Look at, and edit, a live Deployment (slide 395)"
echo "'kubectl edit deployment/wordpress-deployment' opens the live object in an editor."
echo "The same change without an editor:"
run kubectl patch deployment wordpress-deployment -p '{"metadata":{"labels":{"version":"1.1"}}}'
run kubectl get deployments --show-labels
echo "That changed only a label on the Deployment, so no new ReplicaSet and no restart."

step "Done"
echo "wordpress-deployment is running with 3 replicas in the namespace day20."
echo "Next: setup/run.sh day-20/verify.sh"

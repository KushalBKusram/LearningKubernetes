#!/usr/bin/env bash
# Day 19 lab: a first Kubernetes cluster (slides 357-384).
# Runs on the server. Safe to run more than once: the cluster is created only
# when it does not exist, everything else is recreated.
#
# Leaves running:
#   the kind cluster "course" (one node)
#   Headlamp, the dashboard, on port 30089
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./k8s-lib.sh
need_docker
need_k8s_tools

restarts() { kubectl get pod "$1" -o jsonpath='{.status.containerStatuses[0].restartCount}'; }
phase() { kubectl get pod "$1" -o jsonpath='{.status.phase}'; }

step "1. Launch a local cluster (slides 361, 367)"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "The cluster '$CLUSTER' already exists, keeping it."
else
  echo "The slides tick 'Enable Kubernetes' in Docker Desktop. Here kind creates the cluster:"
  run kind create cluster --config kind-cluster.yaml --wait 180s
fi
# kind starts its node containers with --restart on-failure, which does not bring them back after a
# clean shutdown or reboot of the machine. Change it to the policy used throughout this course.
run docker update --restart unless-stopped "$NODE"
echo "The whole cluster is one Docker container on the server:"
run docker ps --filter "name=$NODE" --format '  {{.Names}}  {{.Image}}  {{.Status}}'

ensure_cluster_healthy
use_namespace day19
echo
echo "From here on, every kubectl command runs against this cluster and the namespace day19:"
echo "  kubectl --context $CTX --namespace day19 ..."

step "2. kubectl is connected to a cluster through a context (slide 368)"
run kubectl config get-contexts
echo "The slides switch with 'kubectl config use-context'. These labs name the context on every call instead,"
echo "because another cluster shares this kubeconfig."

step "3. First steps with kubectl (slides 369-370)"
run kubectl version
run kubectl get nodes
run kubectl get pods -A
echo
echo "docker: [resource] [action]  ->  docker container ls"
echo "kubectl: [action] [resource] ->  kubectl get nodes"

step "4. Launching a first pod (slide 372)"
preload_image ubuntu
kubectl delete pod my-ubuntu my-ubuntu2 --ignore-not-found --wait=true >/dev/null
echo "The slides run it with -it and type 'exit'. Here the pod's program ends by itself after 5 seconds:"
run kubectl run my-ubuntu --image=ubuntu -- sh -c 'echo "hello from a pod"; sleep 5'
wait_for "the pod to start" 120 kubectl logs my-ubuntu
run kubectl logs my-ubuntu
echo "Waiting for the program to end, and for Kubernetes to restart the pod's container..."
for _ in $(seq 1 60); do
  [ "$(restarts my-ubuntu)" -ge 1 ] && break
  sleep 2
done
run kubectl get pod my-ubuntu
echo "Restarts: $(restarts my-ubuntu). Unlike 'docker run', Kubernetes started it again (restart policy: Always)."

step "5. The restart policy (slide 373)"
run kubectl run my-ubuntu2 --restart=Never --image=ubuntu -- sh -c 'echo "I run only once"; sleep 5'
for _ in $(seq 1 60); do
  [ "$(phase my-ubuntu2)" = "Succeeded" ] && break
  sleep 2
done
run kubectl get pods
echo "my-ubuntu2: phase $(phase my-ubuntu2), restarts $(restarts my-ubuntu2). With --restart=Never it stays finished."
echo "The third value, OnFailure, restarts only when the program ends with an error."

step "6. To stop the pod (slide 374)"
run kubectl delete pod my-ubuntu my-ubuntu2

step "7. The control plane and the node components (slides 377-379)"
echo "The control plane runs as pods in the namespace kube-system:"
run kubectl get pods -n kube-system -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName
echo
echo "kubelet and the container runtime are ordinary services on the node:"
echo "  kubelet:    $(docker exec "$NODE" systemctl is-active kubelet)"
echo "  containerd: $(docker exec "$NODE" systemctl is-active containerd)"
echo "  runtime reported by the node: $(kubectl get node "$NODE" -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}')"
echo "There is no cloud-controller-manager: it only exists on a cloud provider's cluster."

step "8. How kubectl works: HTTPS requests to the kube-apiserver (slide 380)"
run kubectl cluster-info
echo
echo "'kubectl get nodes' with -v=6 shows the request it sends:"
{ kubectl get nodes -v=6 2>&1 >/dev/null || true; } | sed -nE 's/^.*verb="([A-Z]+)" url="([^"]*)" status="([^"]*)".*$/  \1 \2  ->  \3/p' | head -1 || true
echo "That is the whole mechanism: kubectl sends HTTPS requests to the kube-apiserver and prints the answers."

step "9. Helm, the package manager for Kubernetes (slide 382)"
run helm version --short
run helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ --force-update
echo
echo "Install a chart. The values file sets the options (service type, port):"
run helm upgrade --install day19-headlamp headlamp/headlamp --version 0.46.0 -f headlamp-values.yaml --wait --timeout 5m
run helm list

step "10. The dashboard: a user and a login token (slide 384)"
echo "The slides install the Kubernetes Dashboard. That project was archived in January 2026,"
echo "so this lab installs Headlamp, the dashboard the Kubernetes project now maintains."
kubectl get serviceaccount dashboard-admin >/dev/null 2>&1 || run kubectl create serviceaccount dashboard-admin
kubectl get clusterrolebinding day19-dashboard-admin >/dev/null 2>&1 ||
  run kubectl create clusterrolebinding day19-dashboard-admin --clusterrole=cluster-admin --serviceaccount=day19:dashboard-admin
token=$(kubectl create token dashboard-admin --duration=10m)
echo "A login token for this user can be created at any time (this one: ${#token} characters, not shown)."
echo "Print one for yourself, valid for one hour:  bash day-19/dashboard-token.sh"
echo
echo "The slides reach the dashboard through a proxy. Here it is published on a node port:"
wait_for "the dashboard on port 30089" 60 curl -sf -m 3 -o /dev/null http://localhost:30089 || true
echo "  HTTP status of http://localhost:30089 -> $(curl -s -o /dev/null -m 5 -w '%{http_code}' http://localhost:30089 || true)"

step "Done"
echo "Cluster:   $CLUSTER (context $CTX)"
echo "Dashboard: http://localhost:30089"
echo "Next: setup/run.sh day-19/verify.sh"

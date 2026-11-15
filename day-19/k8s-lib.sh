#!/usr/bin/env bash
# Helpers shared by the Kubernetes days (19-23). Source it after ../setup/lib.sh.

CLUSTER=course
CTX=kind-course
NODE=course-control-plane # the Docker container that is the cluster's only node

# Every kubectl and helm call in these labs goes through the two wrappers below.
# They pin the call to the "course" cluster and to the day's namespace, so a lab
# can never act on another cluster that shares this machine's kubeconfig.
# The labs print commands as the slides show them (kubectl get pods); what runs
# is: kubectl --context kind-course --namespace dayNN get pods
kubectl() { command kubectl --context "$CTX" ${K8S_NAMESPACE:+--namespace "$K8S_NAMESPACE"} "$@"; }
helm() { command helm --kube-context "$CTX" ${K8S_NAMESPACE:+--namespace "$K8S_NAMESPACE"} "$@"; }

# Stop early when the cluster from day 19 is missing or not answering.
need_cluster() {
  need_docker
  need_k8s_tools
  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    echo "The kind cluster '$CLUSTER' does not exist. Run day-19/lab.sh first." >&2
    exit 1
  fi
  if ! kubectl get nodes >/dev/null 2>&1; then
    echo "The kind cluster '$CLUSTER' exists but its API server does not answer." >&2
    exit 1
  fi
}

# Wait until the cluster's own add-ons are ready, restarting any that crashed.
#
# kube-proxy and the storage provisioner open inotify watches. The server has
# a low per-user inotify limit that is shared with every container on the
# machine, so they can fail with "too many open files" while other containers
# are starting. Restarting them once the pressure is gone fixes it.
# (A permanent fix needs sudo: raise fs.inotify.max_user_instances.)
ensure_cluster_healthy() {
  local attempt
  for attempt in 1 2 3 4; do
    if kubectl --namespace kube-system rollout status daemonset/kube-proxy --timeout=45s >/dev/null 2>&1 &&
      kubectl --namespace kube-system rollout status deployment/coredns --timeout=45s >/dev/null 2>&1 &&
      kubectl --namespace local-path-storage rollout status deployment/local-path-provisioner --timeout=45s >/dev/null 2>&1; then
      return 0
    fi
    echo "Cluster add-ons not ready (attempt $attempt of 4), restarting them..." >&2
    kubectl --namespace kube-system delete pod -l k8s-app=kube-proxy --wait=false >/dev/null 2>&1 || true
    kubectl --namespace kube-system delete pod -l k8s-app=kube-dns --wait=false >/dev/null 2>&1 || true
    kubectl --namespace local-path-storage delete pod --all --wait=false >/dev/null 2>&1 || true
    sleep 15
  done
  echo "The cluster add-ons did not become ready. Check for 'too many open files' in:" >&2
  echo "  kubectl --context $CTX -n kube-system logs ds/kube-proxy" >&2
  return 1
}

# Work in one namespace per day, creating it when needed.
use_namespace() {
  K8S_NAMESPACE=$1
  kubectl get namespace "$1" >/dev/null 2>&1 || kubectl create namespace "$1" >/dev/null
}

# Is this image already in the node's own image store?
node_has_image() { docker exec "$NODE" crictl inspecti "$1" >/dev/null 2>&1; }

# Copy an image from the server's Docker into the node when Docker has it and
# the node does not. This saves a download from Docker Hub. When Docker does
# not have the image either, nothing happens and the node pulls it itself.
#
# 'kind load docker-image' fails with "content digest ... not found" for images that
# have several platforms in Docker's image store, so this exports only the node's
# platform and imports that.
preload_image() {
  local image=$1
  node_has_image "$image" && return 0
  if docker image inspect "$image" >/dev/null 2>&1; then
    docker save --platform "linux/$(docker info --format '{{.Architecture}}' | sed 's/x86_64/amd64/;s/aarch64/arm64/')" "$image" 2>/dev/null |
      docker exec -i --privileged "$NODE" ctr --namespace=k8s.io images import --digests --snapshotter=overlayfs - >/dev/null 2>&1 || true
  fi
}

# wait_for "description" timeout-seconds command...   -> polls until the command succeeds.
wait_for() {
  local desc=$1 timeout=$2 waited=0
  shift 2
  until "$@" >/dev/null 2>&1; do
    if [ "$waited" -ge "$timeout" ]; then
      echo "Timed out after ${timeout}s waiting for: $desc" >&2
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

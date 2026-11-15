#!/usr/bin/env bash
# Shared settings for the "eks" cluster of days 24 and 25.
# Source it after ../setup/lib.sh; do not run it.

EKS_CLUSTER=eks
EKS_CONTEXT=kind-eks

# The cluster gets its own kubeconfig file, so nothing here ever reads or changes
# ~/.kube/config (another cluster may live there). Every kubectl and helm call
# also names the context explicitly.
export KUBECONFIG="$HOME/.kube/eks.config"

# kubectl / helm against the eks cluster, for calls whose command line is not shown.
kc() { kubectl --context "$EKS_CONTEXT" "$@"; }
hc() { helm --kube-context "$EKS_CONTEXT" "$@"; }

# The name under which the server is reachable from the Mac.
server_name() {
  local name
  name=$(tailscale status --self --peers=false --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//')
  echo "${name:-$(hostname -f)}"
}

cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$EKS_CLUSTER"; }

need_cluster() {
  if ! cluster_exists || ! kc get nodes >/dev/null 2>&1; then
    echo "The eks cluster is not running. Run day-24/lab.sh first." >&2
    exit 1
  fi
}

# Make sure an image is in the server's Docker (pull only if absent), then copy it
# into the worker nodes. Nodes then never pull it from Docker Hub themselves.
#
# It goes through `docker save --platform` and `kind load image-archive`. The plain
# `kind load docker-image` fails here ("content digest ... not found"): Docker keeps
# multi-platform images, and kind tries to import the platforms that were never pulled.
load_image() {
  local image=$1 ref arch tar node missing=0
  case $image in */*) ref=$image ;; *) ref=docker.io/library/$image ;; esac
  docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >/dev/null
  for node in "$EKS_CLUSTER-worker" "$EKS_CLUSTER-worker2"; do
    docker exec "$node" crictl inspecti "$ref" >/dev/null 2>&1 || missing=1
  done
  [ "$missing" = 0 ] && return 0
  case $(uname -m) in aarch64 | arm64) arch=arm64 ;; *) arch=amd64 ;; esac
  tar=$(mktemp /tmp/day24-image.XXXXXX.tar)
  docker save --platform "linux/$arch" -o "$tar" "$image"
  kind load image-archive "$tar" --name "$EKS_CLUSTER" --nodes "$EKS_CLUSTER-worker,$EKS_CLUSTER-worker2" >/dev/null
  rm -f "$tar"
}

# Wait until a URL answers with the expected HTTP status (default 200).
wait_http() {
  local url=$1 want=${2:-200} i
  shift 2 2>/dev/null || shift $#
  for i in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$@" "$url" 2>/dev/null)" = "$want" ] && return 0
    sleep 1
  done
  return 1
}

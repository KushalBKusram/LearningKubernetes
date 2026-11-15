#!/usr/bin/env bash
# Day 24 lab: the EKS chapter, on a kind cluster (slides 498-533).
# Runs on the server. Safe to run more than once: it creates what is missing and
# re-applies the rest.
#
# Leaves running (kind cluster "eks", 1 control plane + 2 workers):
#   8430 / 8431  NodePort 30080 of nginx, on worker 1 / worker 2
#   8440         "manual load balancer" container (day24-manual-lb) in front of both nodes
#   8480 / 8443  F5 NGINX Ingress Controller, HTTP / HTTPS
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./env.sh
need_docker
need_k8s_tools

METALLB_VERSION=v0.16.2
NGINX_INGRESS_CHART_VERSION=2.8.1 # app version 5.7.1
work=$PWD/.work
mkdir -p "$work" "$HOME/.kube"

body() { curl -s -m 5 "$@" || true; }

step "1. The cluster: eksctl create cluster becomes kind create cluster (slides 503-506)"
if cluster_exists; then
  echo "The cluster '$EKS_CLUSTER' already exists."
else
  run kind create cluster --config cluster.yaml --kubeconfig "$KUBECONFIG"
fi
# kind starts its node containers with --restart on-failure, which does not bring them back after a
# clean shutdown or reboot of the machine. Change it to the policy used throughout this course.
# shellcheck disable=SC2046
run docker update --restart unless-stopped $(kind get nodes --name "$EKS_CLUSTER")
run kubectl --context "$EKS_CONTEXT" wait --for=condition=Ready nodes --all --timeout=180s
run kubectl --context "$EKS_CONTEXT" get nodes -L topology.kubernetes.io/zone -o wide

step "2. nginx behind a NodePort Service (slides 508-509)"
load_image nginx:latest
run kubectl --context "$EKS_CONTEXT" apply -f nginx.yaml
run kubectl --context "$EKS_CONTEXT" rollout status deployment/nginx --timeout=180s
run kubectl --context "$EKS_CONTEXT" get pods -l app=nginx -o wide
run kubectl --context "$EKS_CONTEXT" get service nginx-nodeport
name=$(server_name)
wait_http http://localhost:8430 200 || true
wait_http http://localhost:8431 200 || true
echo "On EKS this port was blocked by the nodes' security group until you opened it."
echo "Here each worker's port 30080 is published on the server by cluster.yaml:"
echo "  node #1 (eu-west-3a) -> :8430 -> $(body http://localhost:8430)"
echo "  node #2 (eu-west-3b) -> :8431 -> $(body http://localhost:8431)"
echo "Either node reaches the Service, whichever node the pod runs on."
echo "Port 8430 several times (kube-proxy picks a pod each time, on either node):"
for _ in 1 2 3 4; do echo "  $(body http://localhost:8430)"; done

step "3. A LoadBalancer Service (slides 511-513)"
echo "Without a cloud, a LoadBalancer Service stays 'pending'. MetalLB plays the part of AWS:"
run kubectl --context "$EKS_CONTEXT" apply -f "https://raw.githubusercontent.com/metallb/metallb/$METALLB_VERSION/config/manifests/metallb-native.yaml"
run kubectl --context "$EKS_CONTEXT" -n metallb-system rollout status deployment/controller --timeout=180s
run kubectl --context "$EKS_CONTEXT" -n metallb-system rollout status daemonset/speaker --timeout=180s
# Addresses from the top of the kind Docker network (IPv4), unused by the nodes.
subnet=$(docker network inspect kind --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/' | head -1)
prefix=$(echo "$subnet" | cut -d. -f1,2)
cat >"$work/metallb-pool.yaml" <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
    - $prefix.255.200-$prefix.255.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - kind-pool
EOF
echo "Address pool: $prefix.255.200-$prefix.255.220 (inside the Docker network $subnet)"
for _ in $(seq 1 30); do
  kc apply -f "$work/metallb-pool.yaml" >/dev/null 2>&1 && break
  sleep 2
done
run kubectl --context "$EKS_CONTEXT" apply -f "$work/metallb-pool.yaml"
lb_ip=""
for _ in $(seq 1 60); do
  lb_ip=$(kc get service nginx-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$lb_ip" ] && break
  sleep 1
done
run kubectl --context "$EKS_CONTEXT" get service nginx-lb
echo "Load balancer address: ${lb_ip:-none}"
echo "From the server: $(body "http://$lb_ip")"
echo "This address exists only on the server's Docker network. The Mac cannot reach it,"
echo "which is why the Mac-facing ports below come from published host ports instead."

step "4. A load balancer created by hand (slides 516-518)"
node_ips=$(docker inspect "$EKS_CLUSTER-worker" "$EKS_CLUSTER-worker2" --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}')
{
  echo "upstream nodes {"
  for ip in $node_ips; do echo "  server $ip:30080;"; done
  echo "}"
  # IPv6 too: "localhost" on the server may resolve to ::1, and the kind network has IPv6.
  echo "server { listen 80; listen [::]:80; location / { proxy_pass http://nodes; } }"
} >"$work/manual-lb.conf"
cat "$work/manual-lb.conf"
docker rm -f day24-manual-lb >/dev/null 2>&1 || true
run docker run -d --restart unless-stopped --name day24-manual-lb --network kind -p 8440:80 -v "$work/manual-lb.conf:/etc/nginx/conf.d/default.conf:ro" nginx:latest
echo "It must be able to reach the nodes' port 30080: the 'security group' rule of slide 513. Here it joins the nodes' network."
wait_http http://localhost:8440 200 || true
echo "A few requests through it:"
for _ in 1 2 3 4; do echo "  $(body http://localhost:8440)"; done
echo "The weak point from slide 518: add a node and this file does not know about it."

step "5. The ingress controller (slides 519-523)"
echo "ingress-nginx, the controller on slide 519, was retired in March 2026 and its repository is archived."
echo "The maintained F5 NGINX Ingress Controller does the same job and is used instead."
run helm --kube-context "$EKS_CONTEXT" upgrade --install nginx-ingress oci://ghcr.io/nginx/charts/nginx-ingress \
  --version "$NGINX_INGRESS_CHART_VERSION" --namespace nginx-ingress --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.httpPort.nodePort=30180 \
  --set controller.service.httpsPort.nodePort=30443 \
  --set controller.service.externalTrafficPolicy=Cluster \
  --set controller.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=128Mi \
  --wait --timeout 300s
run kubectl --context "$EKS_CONTEXT" -n nginx-ingress get pods,service
run kubectl --context "$EKS_CONTEXT" get ingressclass

step "6. A custom image (slide 533)"
run docker build -q -t day24-hello:1 image
echo "Copying the image into both worker nodes (what a pull from ECR would do):"
load_image day24-hello:1
docker exec "$EKS_CLUSTER-worker" crictl images | grep -E 'IMAGE|day24-hello'
run kubectl --context "$EKS_CONTEXT" apply -f hello.yaml
run kubectl --context "$EKS_CONTEXT" rollout status deployment/hello --timeout=180s

step "7. Ingress with HTTPS (slides 519, 525)"
if [ ! -s "$work/tls.crt" ]; then
  run openssl req -x509 -nodes -newkey rsa:2048 -days 365 -subj "/CN=nginx.eks.local" \
    -addext "subjectAltName=DNS:nginx.eks.local,DNS:hello.eks.local" \
    -keyout "$work/tls.key" -out "$work/tls.crt"
fi
# The Secret holds the certificate, where AWS would reference one in Certificate Manager by ARN.
kc create secret tls nginx-eks-tls --cert="$work/tls.crt" --key="$work/tls.key" --dry-run=client -o yaml | kc apply -f - >/dev/null
echo "secret/nginx-eks-tls applied"
run kubectl --context "$EKS_CONTEXT" apply -f ingress.yaml
sleep 5
run kubectl --context "$EKS_CONTEXT" get ingress nginx-ingress
echo
echo "Hostnames matter to an Ingress, so the requests carry them (--resolve points them at the server):"
wait_http https://nginx.eks.local:8443 200 -k --resolve nginx.eks.local:8443:127.0.0.1 || true
wait_http https://hello.eks.local:8443 200 -k --resolve hello.eks.local:8443:127.0.0.1 || true
echo "HTTP  nginx.eks.local -> $(curl -s -m 5 -o /dev/null -w '%{http_code} redirect to %{redirect_url}' -H 'Host: nginx.eks.local' http://localhost:8480)"
echo "HTTPS nginx.eks.local -> $(body -k --resolve nginx.eks.local:8443:127.0.0.1 https://nginx.eks.local:8443)"
echo "HTTPS hello.eks.local -> $(body -k --resolve hello.eks.local:8443:127.0.0.1 https://hello.eks.local:8443)"
echo "The controller sends plain HTTP to HTTPS (the ALB annotations of slide 525 do the same with a listener rule)."
echo "The certificate served:"
echo | timeout 10 openssl s_client -connect localhost:8443 -servername nginx.eks.local 2>/dev/null | openssl x509 -noout -subject -issuer -dates | sed 's/^/  /'

step "8. Routing straight to the pods (slides 527-531)"
echo "A NodePort or LoadBalancer path ends at a Service, and kube-proxy then picks any pod, possibly on another node."
echo "The ingress controller skips the Service: its nginx upstreams are the pod addresses themselves."
pods=$(kc get pods -l app=nginx -o jsonpath='{range .items[*]}{.status.podIP}{" "}{end}')
echo "nginx pod IPs:     $pods"
ctl=$(kc -n nginx-ingress get pods -o name | head -1)
echo "Upstreams inside the controller's nginx configuration:"
kc -n nginx-ingress exec "$ctl" -- sh -c 'grep -h "server " /etc/nginx/conf.d/*.conf | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+" | sort -u' | sed 's/^/  /' || true
echo "On EKS this is the 'target-type: ip' annotation, which needs pods with VPC addresses (the VPC CNI, slide 531)."
echo "In kind the pod addresses are routable inside the cluster, which is all the controller needs."

step "Done"
echo "http://$name:8430 and :8431  NodePort on node 1 / node 2"
echo "http://$name:8440            the manual load balancer"
echo "http://$name:8480            ingress, HTTP  (send Host: nginx.eks.local)"
echo "https://$name:8443           ingress, HTTPS (send SNI nginx.eks.local or hello.eks.local; certificate is self-signed)"
echo "Next: setup/run.sh day-24/verify.sh"

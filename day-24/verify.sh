#!/usr/bin/env bash
# Day 24 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./env.sh
need_docker
need_k8s_tools
need_cluster

get() { curl -s -m 5 "$@"; }
status() { curl -s -o /dev/null -m 5 -w '%{http_code}' "$@"; }
# contains PATTERN command...: run the command to completion first, then search its output.
# (Piping straight into `grep -q` can make curl fail with a broken pipe under pipefail.)
contains() {
  local pattern=$1 out
  shift
  out=$("$@" 2>/dev/null)
  grep -q -- "$pattern" <<<"$out"
}

three_nodes() { [ "$(kc get nodes --no-headers | grep -c ' Ready ')" = "3" ]; }
zones() {
  [ "$(kc get node "$EKS_CLUSTER-worker" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')" = "eu-west-3a" ] &&
    [ "$(kc get node "$EKS_CLUSTER-worker2" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')" = "eu-west-3b" ]
}
nginx_ready() { [ "$(kc get deployment nginx -o jsonpath='{.status.readyReplicas}')" = "2" ]; }
nginx_two_nodes() { [ "$(kc get pods -l app=nginx -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l)" = "2" ]; }
nodeport_30080() { [ "$(kc get service nginx-nodeport -o jsonpath='{.spec.type}:{.spec.ports[0].nodePort}')" = "NodePort:30080" ]; }
via_port() { contains '^nginx pod nginx-' get "http://localhost:$1"; }
lb_address() {
  local ip
  ip=$(kc get service nginx-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  [ -n "$ip" ] && contains '^nginx pod nginx-' get "http://$ip"
}
lb_in_pool() { kc get service nginx-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | grep -qE '^[0-9]+\.[0-9]+\.255\.(2[0-1][0-9]|220)$'; }
manual_lb_balances() {
  local answers nodes
  answers=$(for _ in $(seq 1 30); do get http://localhost:8440; echo; done)
  nodes=$(echo "$answers" | grep -o 'on node [a-z0-9-]*' | sort -u | wc -l)
  [ "$nodes" -eq 2 ]
}
controller_ready() { [ "$(kc -n nginx-ingress get deployment nginx-ingress-controller -o jsonpath='{.status.readyReplicas}')" = "1" ]; }
ingress_class() { kc get ingressclass nginx -o jsonpath='{.spec.controller}' | grep -q 'nginx.org/ingress-controller'; }
http_redirects() { [ "$(status -H 'Host: nginx.eks.local' http://localhost:8480)" = "301" ]; }
https_nginx() { contains '^nginx pod nginx-' get -k --resolve nginx.eks.local:8443:127.0.0.1 https://nginx.eks.local:8443; }
https_hello() { contains 'hello from the custom image day24-hello:1' get -k --resolve hello.eks.local:8443:127.0.0.1 https://hello.eks.local:8443; }
cert_subject() {
  echo | timeout 10 openssl s_client -connect localhost:8443 -servername nginx.eks.local 2>/dev/null |
    openssl x509 -noout -subject | grep -q 'CN *= *nginx.eks.local'
}
unknown_host_404() { [ "$(status -H 'Host: other.eks.local' http://localhost:8480)" = "404" ]; }
upstreams_are_pods() {
  local ctl ip config
  ctl=$(kc -n nginx-ingress get pods -o name | head -1)
  config=$(kc -n nginx-ingress exec "$ctl" -- sh -c 'cat /etc/nginx/conf.d/*.conf')
  for ip in $(kc get pods -l app=nginx -o jsonpath='{range .items[*]}{.status.podIP}{" "}{end}'); do
    echo "$config" | grep -qF "server $ip:80" || return 1
  done
}
custom_image_never_pulled() {
  [ "$(kc get deployment hello -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}')" = "Never" ] &&
    [ "$(kc get deployment hello -o jsonpath='{.status.readyReplicas}')" = "2" ]
}
kubeconfig_isolated() { [ "$KUBECONFIG" = "$HOME/.kube/eks.config" ] && [ -s "$KUBECONFIG" ]; }

step "Day 24 verification"
echo "cluster"
check "the eks cluster has 3 nodes, all Ready" three_nodes
check "workers are in zones eu-west-3a and eu-west-3b" zones
check "the cluster has its own kubeconfig file (~/.kube/eks.config)" kubeconfig_isolated
echo "NodePort (slide 508)"
check "nginx Deployment has 2 ready pods" nginx_ready
check "the 2 pods run on 2 different nodes" nginx_two_nodes
check "Service nginx-nodeport is a NodePort on 30080" nodeport_30080
check "node #1, port 8430: nginx answers" via_port 8430
check "node #2, port 8431: nginx answers" via_port 8431
echo "LoadBalancer (slide 511)"
check "nginx-lb received an address from the MetalLB pool" lb_in_pool
check "the load balancer address answers from the server" lb_address
echo "load balancer made by hand (slide 516)"
check "port 8440 answers and reaches pods on both nodes" manual_lb_balances
echo "Ingress and HTTPS (slides 519, 525)"
check "the ingress controller is ready" controller_ready
check "IngressClass nginx belongs to the F5 NGINX controller" ingress_class
check "HTTP on 8480 redirects (301) to HTTPS" http_redirects
check "HTTPS nginx.eks.local reaches the nginx pods" https_nginx
check "HTTPS hello.eks.local reaches the custom image" https_hello
check "the certificate served is for nginx.eks.local" cert_subject
check "an unknown host gets 404 from the controller" unknown_host_404
echo "straight to the pods (slide 529)"
check "the controller's upstreams are the nginx pod IPs" upstreams_are_pods
echo "custom image (slide 533)"
check "hello runs from a loaded image (imagePullPolicy Never), 2 ready pods" custom_image_never_pulled
summary

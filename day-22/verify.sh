#!/usr/bin/env bash
# Day 22 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_cluster
K8S_NAMESPACE=day22

# contains <text>: reads all of stdin, then looks for the text. (grep -q stops reading early, so the
# program feeding it, curl, can die of SIGPIPE and "pipefail" would report a failure for a match.)
contains() { local data; data=$(cat); [[ $data == *"$1"* ]]; }
jp() { kubectl get "$1" -o jsonpath="$2"; }
wp_pod() { kubectl get pods -l app=wordpress -o jsonpath='{.items[0].metadata.name}'; }
# tcp_from <host> <port>: can a WordPress pod open a TCP connection?
tcp_from() { kubectl exec "$(wp_pod)" -- timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" >/dev/null 2>&1; }
http_code() { curl -s -L -m 10 -o /dev/null -w '%{http_code}' "$1"; }

db_ready() { [ "$(jp statefulset/mariadb-statefulset '{.status.readyReplicas}')" = "1" ]; }
wp_ready() { [ "$(jp deployment/wordpress-deployment '{.status.readyReplicas}')" = "3" ]; }
svc_type() { [ "$(jp "service/$1" '{.spec.type}')" = "$2" ]; }
svc_clusterip() { [ -n "$(jp service/mariadb-service '{.spec.clusterIP}')" ] && [ "$(jp service/mariadb-service '{.spec.clusterIP}')" != None ]; }
endpoint_is_pod() {
  [ "$(kubectl get endpointslices -l kubernetes.io/service-name=mariadb-service -o jsonpath='{.items[*].endpoints[*].addresses[0]}')" = "$(jp pod/mariadb-statefulset-0 '{.status.podIP}')" ]
}
wordpress_endpoints() { [ "$(kubectl get endpointslices -l kubernetes.io/service-name=wordpress-service -o jsonpath='{.items[*].endpoints[*].addresses[0]}' | wc -w)" = "3" ]; }
dns_short() { kubectl exec "$(wp_pod)" -- getent hosts mariadb-service | grep -q "$(jp service/mariadb-service '{.spec.clusterIP}')"; }
dns_full() { kubectl exec "$(wp_pod)" -- getent hosts mariadb-service.day22.svc.cluster.local | grep -q "$(jp service/mariadb-service '{.spec.clusterIP}')"; }
db_login_by_name() {
  kubectl exec "$(wp_pod)" -- php -r '$m = new mysqli(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME")); exit($m->connect_error ? 1 : 0);'
}
service_survives_pod_change() {
  local ip_before ip_after
  ip_before=$(jp service/mariadb-service '{.spec.clusterIP}')
  kubectl delete pod mariadb-statefulset-0 --wait=true >/dev/null || return 1
  wait_for "database pod" 240 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s || return 1
  ip_after=$(jp service/mariadb-service '{.spec.clusterIP}')
  [ "$ip_before" = "$ip_after" ] && wait_for "service to reach the new pod" 60 tcp_from mariadb-service 3306
}
nodeport_set() { [ "$(jp "service/$1" '{.spec.ports[0].nodePort}')" = "$2" ]; }
page_has_wordpress() { curl -s -L -m 10 "$1" | contains 'WordPress'; }
three_ports_differ() {
  [ "$(jp service/wordpress-ports '{.spec.ports[0].port}')" = 8080 ] &&
    [ "$(jp service/wordpress-ports '{.spec.ports[0].targetPort}')" = 80 ] &&
    [ "$(jp service/wordpress-ports '{.spec.ports[0].nodePort}')" = 30081 ]
}
inside_uses_service_port() { tcp_from wordpress-ports 8080 && ! tcp_from wordpress-ports 80; }
named_port() {
  [ "$(jp service/wordpress-service '{.spec.ports[0].targetPort}')" = http ] &&
    [ "$(jp deployment/wordpress-deployment '{.spec.template.spec.containers[0].ports[0].name}')" = http ]
}
loadbalancer_pending() {
  kubectl create service loadbalancer verify-lb --tcp=80:80 >/dev/null 2>&1 || return 1
  sleep 4
  local ip
  ip=$(jp service/verify-lb '{.status.loadBalancer.ingress[0].ip}')
  kubectl delete service verify-lb >/dev/null 2>&1
  [ -z "$ip" ]
}
failover() {
  local victim ok=0 i
  victim=$(kubectl get pods -l app=wordpress -o jsonpath='{.items[0].metadata.name}')
  kubectl delete pod "$victim" --wait=false >/dev/null || return 1
  for i in $(seq 1 15); do
    [ "$(http_code http://localhost:30080)" = "200" ] && ok=$((ok + 1))
    sleep 1
  done
  wait_for "3 ready pods" 120 kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 deployment/wordpress-deployment --timeout=5s
  [ "$ok" -ge 14 ]
}
no_expose_leftovers() { ! kubectl get service wordpress-exposed >/dev/null 2>&1 && ! kubectl get service lb-demo >/dev/null 2>&1; }

step "Day 22 verification"
echo "pods and Services"
check "MariaDB StatefulSet has 1 ready pod" db_ready
check "WordPress Deployment has 3 ready pods" wp_ready
check "mariadb-service is a ClusterIP Service with an address" svc_type mariadb-service ClusterIP
check "mariadb-service has a cluster IP" svc_clusterip
check "the Service's endpoint is the database pod's IP" endpoint_is_pod
check "wordpress-service has 3 endpoints" wordpress_endpoints
check "the temporary Services from the lab are gone" no_expose_leftovers
echo "DNS"
check "'mariadb-service' resolves to the Service's cluster IP" dns_short
check "'mariadb-service.day22.svc.cluster.local' resolves to it too" dns_full
check "WordPress logs in to the database through the name mariadb-service" db_login_by_name
check "replacing the database pod keeps the Service's IP and it reaches the new pod" service_survives_pod_change
echo "Service types and ports"
check "wordpress-service is a NodePort Service on 30080" nodeport_set wordpress-service 30080
check "wordpress-ports is a NodePort Service on 30081" nodeport_set wordpress-ports 30081
check "port, targetPort and nodePort of wordpress-ports are 8080, 80 and 30081" three_ports_differ
check "inside the cluster wordpress-ports answers on 8080 and not on 80" inside_uses_service_port
check "the pods' port is named http and the Service refers to the name" named_port
check "a LoadBalancer Service never gets an external IP on this cluster" loadbalancer_pending
echo "from outside"
check "http://localhost:30080 shows WordPress" page_has_wordpress http://localhost:30080
check "http://localhost:30081 shows WordPress" page_has_wordpress http://localhost:30081
check "the NodePort is reachable on the server's Tailscale address" page_has_wordpress "http://$(tailscale ip -4 | head -1):30080"
check "killing a WordPress pod does not interrupt the service (14 of 15 requests ok)" failover
summary

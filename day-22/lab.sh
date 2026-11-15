#!/usr/bin/env bash
# Day 22 lab: networking in Kubernetes, Services (slides 442-467).
# Runs on the server, in the namespace day22 of the cluster from day 19.
# Safe to run more than once: it starts by emptying its own namespace.
#
# Leaves running: MariaDB (+ ClusterIP Service), WordPress x3 (+ NodePort Services on 30080 and 30081).
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-19/k8s-lib.sh
need_cluster
ensure_cluster_healthy
use_namespace day22

first_pod() { kubectl get pods -l "$1" -o jsonpath='{.items[0].metadata.name}'; }
pod_ip() { kubectl get pod "$1" -o jsonpath='{.status.podIP}'; }
# tcp_from <pod> <host> <port>: can a pod open a TCP connection? (bash /dev/tcp; the image has no nc or curl)
tcp_from() { kubectl exec "$1" -- timeout 4 bash -c "exec 3<>/dev/tcp/$2/$3" >/dev/null 2>&1; }
yesno() { "$@" && echo yes || echo no; }
final_url_title() { curl -s -L -m 10 -o /tmp/day22-page.html -w '%{url_effective}' "$1"; echo " -> $(grep -o '<title>[^<]*' /tmp/day22-page.html | head -1 | sed 's/<title>//')"; }

step "0. Start clean, and give the node the images it needs"
kubectl delete deployment,statefulset,service,pod --all --wait=true >/dev/null 2>&1 || true
kubectl delete secret my-mariadb-secret --ignore-not-found >/dev/null
for image in ubuntu mariadb:latest wordpress:latest; do preload_image "$image"; done
run kubectl apply -f secret.yaml
run kubectl apply -f mariadb.yaml
wait_for "the database pod" 180 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s
run kubectl apply -f wordpress.yaml
run kubectl rollout status deployment/wordpress-deployment --timeout=240s

step "1. Every pod has its own IP address (slide 445)"
run kubectl get pods -o wide
wp=$(first_pod app=wordpress)
db_ip=$(pod_ip mariadb-statefulset-0)
echo
echo "The database pod's IP is $db_ip. From the WordPress pod $wp, any pod can open a connection to any other:"
echo "  can $wp reach $db_ip:3306? $(yesno tcp_from "$wp" "$db_ip" 3306)"

step "2. The problem with IP addresses (slide 448)"
echo "Pods come and go, and a new pod gets a new IP. Replace the database pod:"
run kubectl delete pod mariadb-statefulset-0
wait_for "the new database pod" 180 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s
new_ip=$(pod_ip mariadb-statefulset-0)
echo "Old IP: $db_ip    New IP: $new_ip"
echo "  can $wp reach the old IP $db_ip:3306? $(yesno tcp_from "$wp" "$db_ip" 3306)"
echo "  can $wp reach the new IP $new_ip:3306? $(yesno tcp_from "$wp" "$new_ip" 3306)"
echo "Anything that had the old IP written down is now broken. A Service fixes that."

step "3. A Service: one stable address in front of the pods (slides 449, 454)"
run kubectl get service mariadb-service
svc_ip=$(kubectl get service mariadb-service -o jsonpath='{.spec.clusterIP}')
echo "The Service has its own cluster-internal IP, $svc_ip. It forwards to the pods found through its selector (app=mariadb):"
run kubectl get endpointslices -l kubernetes.io/service-name=mariadb-service
echo "  pod IPs behind the Service: $(kubectl get endpointslices -l kubernetes.io/service-name=mariadb-service -o jsonpath='{.items[*].endpoints[*].addresses[*]}')"
echo "  can $wp reach the Service $svc_ip:3306? $(yesno tcp_from "$wp" "$svc_ip" 3306)"

step "4. Automatic failover (slides 450-452)"
echo "Replace the database pod once more. The Service's address stays; the pod behind it changes:"
before_pod_ip=$(pod_ip mariadb-statefulset-0)
run kubectl delete pod mariadb-statefulset-0
wait_for "the new database pod" 180 kubectl wait --for=condition=Ready pod/mariadb-statefulset-0 --timeout=5s
wait_for "the endpoint to follow the pod" 60 kubectl wait --for=jsonpath='{.status.podIP}'="$(pod_ip mariadb-statefulset-0)" pod/mariadb-statefulset-0 --timeout=5s
echo "  pod IP:     $before_pod_ip -> $(pod_ip mariadb-statefulset-0)"
echo "  Service IP: $svc_ip -> $(kubectl get service mariadb-service -o jsonpath='{.spec.clusterIP}') (unchanged)"
wait_for "the Service to reach the new pod" 60 tcp_from "$wp" "$svc_ip" 3306
echo "  can $wp reach the Service $svc_ip:3306? $(yesno tcp_from "$wp" "$svc_ip" 3306)"

step "5. kubectl expose: a Service from the command line (slide 454)"
run kubectl expose deployment wordpress-deployment --name=wordpress-exposed --port=80
run kubectl get service wordpress-exposed -o wide
echo "It copied the Deployment's selector. YAML gives many more options, so the lab uses YAML from here on."
run kubectl delete service wordpress-exposed

step "6. Several objects in one YAML file (slide 456)"
echo "mariadb.yaml holds $(grep -c '^kind:' mariadb.yaml) objects separated by '---': $(grep '^kind:' mariadb.yaml | awk '{print $2}' | paste -sd, -)."
echo "wordpress.yaml holds $(grep -c '^kind:' wordpress.yaml) objects: $(grep '^kind:' wordpress.yaml | awk '{print $2}' | paste -sd, -)."
run kubectl get all -l app=mariadb

step "7. DNS: Services are reachable by name (slide 458)"
echo "Kubernetes runs its own DNS server, CoreDNS:"
run kubectl get pods -n kube-system -l k8s-app=kube-dns
echo
echo "The slides install dnsutils for nslookup. This image has 'getent', which asks the same resolver:"
run kubectl exec "$wp" -- getent hosts mariadb-service
echo "The full name is <service>.<namespace>.svc.cluster.local:"
run kubectl exec "$wp" -- getent hosts mariadb-service.day22.svc.cluster.local
echo "The short name works because the pod's resolver searches the pod's own namespace first:"
run kubectl exec "$wp" -- grep -E '^(search|nameserver)' /etc/resolv.conf
echo
echo "WordPress already uses it: its setting WORDPRESS_DB_HOST is just 'mariadb-service'. Proof, a login from the WordPress pod:"
run kubectl exec "$wp" -- php -r '$m = new mysqli(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME")); echo $m->connect_error ?: "connected to database " . getenv("WORDPRESS_DB_NAME") . " on " . $m->host_info, "\n";'

step "8. Types of Service (slide 460)"
echo "ClusterIP (the default): only inside the cluster. That is mariadb-service."
echo "LoadBalancer: needs a cloud provider to create the load balancer. This cluster has none:"
run kubectl create service loadbalancer lb-demo --tcp=80:80
sleep 3
run kubectl get service lb-demo
echo "EXTERNAL-IP stays <pending> forever here. On AWS it would get an address (day 24)."
run kubectl delete service lb-demo
echo
echo "NodePort: a ClusterIP plus a port opened on every node:"
run kubectl get services

step "9. The NodePort Service: WordPress from outside (slides 462-463)"
wait_for "WordPress on 30080" 90 curl -s -m 5 -o /dev/null http://localhost:30080
echo "From the server:  $(final_url_title http://localhost:30080)"
echo "WordPress reached the database and shows its installer. The same address works from the Mac:"
echo "  http://$(public_name):30080"
echo "(The cluster config of day 19 publishes the node's ports 30080-30089 on the server.)"

step "10. Three ports (slide 465)"
cat <<'EOF'
  wordpress-service:   port 80   -> targetPort http (80) , nodePort 30080
  wordpress-ports:     port 8080 -> targetPort 80        , nodePort 30081
EOF
run kubectl get services wordpress-service wordpress-ports
echo
echo "Inside the cluster you use the Service's port:"
echo "  $wp -> wordpress-ports:8080 ? $(yesno tcp_from "$wp" wordpress-ports 8080)"
echo "  $wp -> wordpress-ports:80   ? $(yesno tcp_from "$wp" wordpress-ports 80)  (that port is not the Service's)"
echo "  $wp -> wordpress-ports:30081 ? $(yesno tcp_from "$wp" wordpress-ports 30081) (the node port is not opened on the Service address)"
echo "From outside you use the node port:"
echo "  http://localhost:30081 -> $(curl -s -L -m 10 -o /dev/null -w 'HTTP %{http_code}' http://localhost:30081)"

step "11. Named ports (slide 467)"
echo "The pods name their port (ports: - name: http) and wordpress-service points at the name (targetPort: http)."
echo "The name resolves to the number. The Service says: targetPort $(kubectl get service wordpress-service -o jsonpath='{.spec.ports[0].targetPort}')."
echo "Its endpoints, the pods' actual addresses, use the number: port $(kubectl get endpointslices -l kubernetes.io/service-name=wordpress-service -o jsonpath='{.items[0].ports[0].port}')."
echo "If the container's port changes, only the pod template has to change, not every Service."

step "12. A pod dies while the Service is in use (slides 450-452)"
echo "30 requests to http://localhost:30080, one per second. After 10, one WordPress pod is deleted:"
ok=0
for i in $(seq 1 30); do
  if [ "$i" -eq 10 ]; then
    victim=$(first_pod app=wordpress)
    kubectl delete pod "$victim" --wait=false >/dev/null
    echo "  [request 10] deleted pod $victim"
  fi
  code=$(curl -s -L -m 5 -o /dev/null -w '%{http_code}' http://localhost:30080 || true)
  [ "$code" = "200" ] && ok=$((ok + 1))
  sleep 1
done
echo "  $ok of 30 requests answered with HTTP 200"
wait_for "3 ready pods again" 120 kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 deployment/wordpress-deployment --timeout=5s
run kubectl get pods -l app=wordpress

step "Done"
echo "WordPress:  http://$(public_name):30080 (installer page; no storage yet, that is day 23)"
echo "Next: setup/run.sh day-22/verify.sh"

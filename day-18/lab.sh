#!/usr/bin/env bash
# Day 18 lab: ECS part 2 - shared storage, SFTP access, load balancer, HTTPS,
# WordPress with an external database (slides 338-356).
# Runs on the server. Docker Swarm stands in for ECS, as on day 17.
#
# Safe to run more than once, but every run starts from scratch: uploaded
# pictures and the WordPress site are wiped. Only the load balancer's
# certificate authority is kept, so its certificate stays the same.
#
# Leaves running:
#   stack day18          services php (2 tasks), lb (1), wordpress (2)
#   day18-rds            MariaDB outside the stack, the stand-in for Amazon RDS
#   day18-sftp           stopped, the stand-in for Transfer Family, "turned off"
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker
. ./common.sh

html=/var/www/html
ensure_image() { docker image inspect "$1" >/dev/null 2>&1 || run docker pull -q "$1"; }
sftp_batch() {
  sftp -q -P 8522 -i "$work/sftp_key" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$work/known_hosts" \
    -b - upload@127.0.0.1
}

day18_teardown day18-caddy-data
rm -rf "$work"
mkdir -p "$work"
chmod 700 "$work"

step "1. The cluster from day 17 (slide 336)"
if [ "$(docker info -f '{{.Swarm.LocalNodeState}}')" = "active" ]; then
  echo "Swarm mode is active: the cluster from day 17 is reused."
else
  run docker swarm init --advertise-addr 127.0.0.1
fi
echo "Name of this server, used for HTTPS: $DOMAIN"

step "2. A file system that several containers mount at once (slide 339)"
run docker volume create day18-efs
run docker run -d --name day18-efs-a -v day18-efs:/mnt/efs ubuntu sleep 300
run docker run -d --name day18-efs-b -v day18-efs:/mnt/efs ubuntu sleep 300
run docker exec day18-efs-a sh -c 'echo "written by container A" > /mnt/efs/hello.txt'
echo "Container B reads the same file system at the same time:"
run docker exec day18-efs-b cat /mnt/efs/hello.txt
docker exec day18-efs-b rm /mnt/efs/hello.txt
docker rm -f day18-efs-a day18-efs-b >/dev/null

step "3. Access from outside: an SFTP server in front of the file system (slide 342)"
run docker build -q -t day18-sftp:v1 sftp
echo "A key pair for the upload (slide 68):"
run ssh-keygen -q -t ed25519 -N '' -C day18-lab -f "$work/sftp_key"
run docker run -d --name day18-sftp -p 8522:22 -v day18-efs:/srv/sftp/site \
  -e SFTP_PUBLIC_KEY="$(cat "$work/sftp_key.pub")" day18-sftp:v1
for _ in $(seq 1 30); do
  docker logs day18-sftp 2>&1 | grep -q 'Server listening' && break
  sleep 1
done

step "4. Upload the application over SFTP (slide 341)"
echo "\$ sftp -P 8522 -i .work/sftp_key upload@localhost"
sftp_batch <<'EOF'
put app/index.php
put app/style.css
ls -l
EOF
echo
echo "The server only transfers files. A shell login is refused:"
ssh -p 8522 -i "$work/sftp_key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$work/known_hosts" upload@127.0.0.1 true 2>&1 | sed 's/^/  /' || true

step "5. A service whose tasks mount the file system, behind a load balancer (slides 344-347)"
ensure_image php:apache
run docker build -q -t day18-lb:v1 lb
run docker volume create day18-caddy-data
echo "The network the tasks, the load balancer and the database share (the stand-in for the VPC):"
run docker network create --driver overlay --attachable day18-net
export DOMAIN
run docker stack deploy --detach=true --resolve-image never -c stack.yaml day18
wait_service day18_php 2
wait_service day18_lb 1
lb=$(docker ps -q --filter name=day18_lb | head -1)
for _ in $(seq 1 60); do
  docker cp "$lb:/data/caddy/pki/authorities/local/root.crt" "$work/root.crt" >/dev/null 2>&1 && break
  sleep 1
done
for _ in $(seq 1 60); do
  [ "$(lbcurl -o /dev/null -w '%{http_code}' "$upload_url/")" = "200" ] && break
  sleep 1
done
run docker service ls --filter name=day18_
echo
echo "Only the load balancer publishes ports. The php service has none:"
echo "  day18_php ports: $(docker service inspect day18_php -f '{{if .Endpoint.Ports}}{{json .Endpoint.Ports}}{{else}}none{{end}}')"
echo "  day18_lb  ports: $(docker service inspect day18_lb -f '{{range .Endpoint.Ports}}{{.PublishedPort}} {{end}}')"

step "6. The target group keeps itself up to date (slide 347)"
echo "Targets the load balancer knows for the php service:"
targets day18_php | sed 's/^/  /'
echo "12 requests to $upload_url, counted per answering task:"
served_by 12
echo
run docker service scale --detach day18_php=3
wait_service day18_php 3
sleep 7 # the load balancer refreshes its target list every 5 seconds
echo "Targets after scaling, with no change to the load balancer:"
targets day18_php | sed 's/^/  /'
echo "12 requests, counted per answering task:"
served_by 12

step "7. One upload, visible to every task (slide 329)"
python3 make-sample-image.py "$work/sample.png"
echo "\$ curl -F image=@.work/sample.png $upload_url/"
stored=$(lbcurl -o /dev/null -D - -F "image=@$work/sample.png" "$upload_url/" | tr -d '\r' | awk 'tolower($1) == "x-stored-as:" { print $2 }')
echo "$stored" >"$work/uploaded-name"
echo "Stored as $stored. One task received it, but all of them have it:"
for task in $(docker ps -q --filter name=day18_php); do
  echo "  task $(docker inspect -f '{{.Config.Hostname}}' "$task"): $(docker exec "$task" ls -l "$html/uploads/$stored")"
done
codes=$(for _ in $(seq 1 6); do lbcurl -o /dev/null -w '%{http_code} ' "$upload_url/uploads/$stored"; done)
echo "Fetching the picture 6 times through the load balancer: $codes"
echo "A file that is not a picture is refused: HTTP $(lbcurl -o /dev/null -w '%{http_code}' -F "image=@app/index.php" "$upload_url/")"

step "8. HTTPS on the load balancer (slides 346, 351)"
echo "The certificate the load balancer presents:"
openssl s_client -connect 127.0.0.1:8543 -servername "$DOMAIN" </dev/null 2>/dev/null |
  openssl x509 -noout -issuer -enddate -ext subjectAltName | sed 's/^/  /'
echo "The php tasks know nothing about it. They are still reached over plain HTTP, port 80."
echo
echo "Plain HTTP on port 8580 only redirects to HTTPS:"
lbcurl -o /dev/null -D - "$redirect_url/some/page" | tr -d '\r' | grep -iE '^(HTTP|location)' | sed 's/^/  /'
echo
echo "A client that does not know the load balancer's certificate authority refuses the connection:"
curl -sS -m 5 -o /dev/null --resolve "$DOMAIN:8543:127.0.0.1" "$upload_url/" 2>&1 | head -1 | sed 's/^/  /' || true

step "9. Project 2: a database outside the cluster (slides 330, 353)"
ensure_image mariadb:latest
db_password=$(openssl rand -hex 16)
(
  umask 077
  printf 'MARIADB_DATABASE=wordpress\nMARIADB_USER=wordpress\nMARIADB_PASSWORD=%s\nMARIADB_RANDOM_ROOT_PASSWORD=1\n' "$db_password" >"$work/rds.env"
  printf 'MYSQL_PWD=%s\n' "$db_password" >"$work/rds-client.env"
  printf '%s' "$(openssl rand -hex 12)" >"$work/wp-admin-password"
)
echo "Generated a database password and a WordPress admin password into day-18/.work on the server."
run docker run -d --name day18-rds --network day18-net --restart unless-stopped \
  -v day18-rds-data:/var/lib/mysql --env-file "$work/rds.env" \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 3s mariadb:latest
for _ in $(seq 1 90); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' day18-rds)" = "healthy" ] && break
  sleep 1
done
echo "Database state: $(docker inspect -f '{{.State.Health.Status}}' day18-rds)"
echo "It is a plain container, not one of the cluster's services:"
docker service ls --filter name=day18_ --format 'service: {{.Name}}' | sed 's/^/  /'

step "10. WordPress as a service, using that database (slide 353)"
ensure_image wordpress:latest
run docker volume create day18-wp-efs
export DB_PASSWORD=$db_password
run docker stack deploy --detach=true --resolve-image never -c stack.yaml -c stack-wordpress.yaml day18
echo "The stack files are the desired state, so php is back at the 2 tasks they ask for."
wait_service day18_wordpress 1
wait_service day18_php 2
for _ in $(seq 1 120); do
  [ "$(lbcurl -o /dev/null -w '%{http_code}' "$blog_url/wp-admin/install.php")" = "200" ] && break
  sleep 1
done
echo "WordPress answers. Running its installer through the load balancer:"
lbcurl -o "$work/wp-install.html" "$blog_url/wp-admin/install.php?step=2" \
  --data-urlencode 'weblog_title=Day 18 blog' \
  --data-urlencode 'user_name=admin' \
  --data-urlencode "admin_password@$work/wp-admin-password" \
  --data-urlencode "admin_password2@$work/wp-admin-password" \
  --data-urlencode 'admin_email=admin@example.com' \
  -d 'pw_weak=1' -d 'blog_public=0' -d 'language='
if grep -q 'Success' "$work/wp-install.html"; then
  echo "  installed (user: admin, password: in day-18/.work/wp-admin-password on the server)"
else
  echo "  UNEXPECTED: the installer did not report success"
fi
echo
echo "With the site installed and its files on the shared volume, a second task can join:"
run docker service scale --detach day18_wordpress=2
wait_service day18_wordpress 2
sleep 7
echo "Front page: $(lbcurl -L "$blog_url/" | grep -o '<title>[^<]*</title>' | head -1)"
echo "Tables WordPress created in the external database: $(docker exec --env-file "$work/rds-client.env" day18-rds mariadb -u wordpress wordpress -N -e 'SHOW TABLES' | wc -l)"

step "11. Turn the SFTP server off again (slide 342)"
echo "On AWS, Transfer Family is billed by the hour. It is only needed while uploading."
run docker stop day18-sftp

step "Done"
docker service ls --filter name=day18_ --format '{{.Name}}: {{.Replicas}}' | sed 's/^/  /'
echo "  upload form: $upload_url"
echo "  WordPress:   $blog_url"
echo "Next: setup/run.sh day-18/verify.sh, then day-18/from-mac.sh on the Mac"

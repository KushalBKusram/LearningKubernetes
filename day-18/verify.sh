#!/usr/bin/env bash
# Day 18 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker
. ./common.sh

html=/var/www/html
stored=$(cat "$work/uploaded-name" 2>/dev/null || echo missing)

swarm_active() { [ "$(docker info -f '{{.Swarm.LocalNodeState}}')" = "active" ]; }
replicas_are() { [ "$(service_replicas "$1")" = "$2" ]; }
no_published_ports() { [ "$(docker service inspect "$1" -f '{{len .Endpoint.Ports}}')" = "0" ]; }
php_is_official_image() { docker service inspect day18_php -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' | grep -q '^php:apache'; }
all_php_tasks_mount_efs() {
  local task n=0
  for task in $(docker ps -q --filter name=day18_php); do
    [ "$(docker inspect "$task" -f '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Name}}{{end}}{{end}}')" = "day18-efs" ] || return 1
    n=$((n + 1))
  done
  [ "$n" -ge 2 ]
}
app_came_by_sftp() { docker run --rm -v day18-efs:/mnt/efs:ro ubuntu test -f /mnt/efs/index.php -a -f /mnt/efs/style.css; }
# grep without -q reads the whole page; with -q it would stop early and make curl fail.
form_ok() { lbcurl "$upload_url/" | grep -F '<title>Day 18: memories</title>' >/dev/null; }
two_tasks_answer() { [ "$(served_by 8 | wc -l)" -ge 2 ]; }
targets_match_tasks() { [ "$(targets day18_php | wc -l)" -eq "$(docker ps -q --filter name=day18_php | wc -l)" ]; }
upload_on_every_task() {
  local task
  for task in $(docker ps -q --filter name=day18_php); do
    docker exec "$task" test -f "$html/uploads/$stored" || return 1
  done
}
upload_served() {
  local i
  for i in 1 2 3 4; do
    [ "$(lbcurl -o /dev/null -w '%{http_code}' "$upload_url/uploads/$stored")" = "200" ] || return 1
  done
}
rejects_non_image() { [ "$(lbcurl -o /dev/null -w '%{http_code}' -F "image=@app/index.php" "$upload_url/")" = "415" ]; }
cert_from_caddy_ca() {
  openssl s_client -connect 127.0.0.1:8543 -servername "$DOMAIN" </dev/null 2>/dev/null |
    openssl x509 -noout -issuer -ext subjectAltName | tr '\n' ' ' | grep -q "Caddy Local Authority.*DNS:$DOMAIN"
}
untrusted_without_ca() { ! curl -s -m 5 -o /dev/null --resolve "$DOMAIN:8543:127.0.0.1" "$upload_url/"; }
http_redirects() {
  lbcurl -o /dev/null -D - "$redirect_url/x" | tr -d '\r' | grep -qi "^location: https://$DOMAIN:8543/x$"
}
sftp_is_off() { [ "$(docker inspect -f '{{.State.Running}}' day18-sftp)" = "false" ]; }
rds_running() { [ "$(docker inspect -f '{{.State.Health.Status}}' day18-rds)" = "healthy" ]; }
rds_outside_cluster() { [ -z "$(docker inspect -f '{{index .Config.Labels "com.docker.swarm.service.name"}}' day18-rds)" ]; }
rds_has_wp_tables() {
  docker exec --env-file "$work/rds-client.env" day18-rds mariadb -u wordpress wordpress -N -e 'SHOW TABLES' | grep -q '_options$'
}
blog_ok() { lbcurl -L "$blog_url/" | grep -F '<title>Day 18 blog</title>' >/dev/null; }
every_wp_task_serves() {
  local task n=0
  for task in $(docker ps -q --filter name=day18_wordpress); do
    [ "$(docker exec "$task" curl -s -o /dev/null -w '%{http_code}' -H "Host: $DOMAIN:8544" -H 'X-Forwarded-Proto: https' http://localhost/)" = "200" ] || return 1
    n=$((n + 1))
  done
  [ "$n" -eq 2 ]
}

step "Day 18 verification"
echo "cluster and services"
check "swarm mode is active" swarm_active
check "service day18_php has 2 of 2 tasks running" replicas_are day18_php 2/2
check "service day18_lb has 1 of 1 tasks running" replicas_are day18_lb 1/1
check "service day18_wordpress has 2 of 2 tasks running" replicas_are day18_wordpress 2/2
echo "shared storage and SFTP (EFS, Transfer Family)"
check "the php service runs the unchanged official image" php_is_official_image
check "every php task mounts the volume day18-efs" all_php_tasks_mount_efs
check "the application files are on the volume (uploaded over SFTP)" app_came_by_sftp
check "the picture uploaded through one task exists on every task" upload_on_every_task
check "the picture is served on repeated requests" upload_served
check "a file that is not a picture is refused with 415" rejects_non_image
check "the SFTP server is turned off again" sftp_is_off
echo "load balancer and HTTPS"
check "the upload form loads over HTTPS, certificate verified against Caddy's CA" form_ok
check "php and wordpress publish no ports of their own" eval 'no_published_ports day18_php && no_published_ports day18_wordpress'
check "requests are answered by more than one php task" two_tasks_answer
check "the load balancer's target list matches the running php tasks" targets_match_tasks
check "the certificate is issued by Caddy's CA for $DOMAIN" cert_from_caddy_ca
check "a client without that CA refuses the connection" untrusted_without_ca
check "plain HTTP on 8580 redirects to HTTPS on 8543" http_redirects
echo "WordPress and its external database (RDS)"
check "day18-rds is healthy" rds_running
check "day18-rds is a plain container, not a service of the cluster" rds_outside_cluster
check "WordPress created its tables in day18-rds" rds_has_wp_tables
check "the blog's front page loads over HTTPS" blog_ok
check "both WordPress tasks serve the site" every_wp_task_serves
summary

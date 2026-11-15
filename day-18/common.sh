#!/usr/bin/env bash
# Shared by day 18's lab.sh, verify.sh and cleanup.sh. Source it from day-18/.

work=$PWD/.work # scratch space on the server: keys, generated passwords, the CA certificate

# The name clients use for this server. It ends up in the HTTPS certificate.
DOMAIN=${COURSE_DOMAIN:-$(tailscale status --self --peers=false --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//')}
[ -n "$DOMAIN" ] || DOMAIN=$(hostname -f)

upload_url=https://$DOMAIN:8543
blog_url=https://$DOMAIN:8544
redirect_url=http://$DOMAIN:8580

# curl through the load balancer on this machine, trusting only the load
# balancer's own certificate authority.
lbcurl() {
  curl -s -m 15 --cacert "$work/root.crt" \
    --resolve "$DOMAIN:8543:127.0.0.1" --resolve "$DOMAIN:8544:127.0.0.1" --resolve "$DOMAIN:8580:127.0.0.1" \
    "$@"
}

# "2/2" for a service name, empty if the service does not exist.
service_replicas() {
  docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | awk -v name="$1" '$1 == name { print $2 }'
}

# wait_service NAME N: until N of N tasks are running.
wait_service() {
  local i
  for i in $(seq 1 120); do
    [ "$(service_replicas "$1")" = "$2/$2" ] && return 0
    sleep 1
  done
  echo "Timed out waiting for $1 to reach $2 running tasks (now: $(service_replicas "$1"))" >&2
  return 1
}

# The target group: the addresses the cluster's DNS lists for a service's tasks,
# asked from inside the load balancer.
targets() {
  local lb
  lb=$(docker ps -q --filter name=day18_lb | head -1)
  docker exec "$lb" nslookup "tasks.$1" 2>/dev/null | awk '/^Address/ && $2 !~ /:53$/ { print $2 }' | sort -u
}

# served_by N: N requests to the upload form, counted per answering task.
served_by() {
  local i
  for i in $(seq 1 "$1"); do
    lbcurl -o /dev/null -D - "$upload_url/" | tr -d '\r' | awk 'tolower($1) == "x-served-by:" { print $2 }'
  done | sort | uniq -c
}

# Remove everything day 18 created, except the volumes named as arguments to keep.
# Usage: day18_teardown [volume-to-keep ...]
day18_teardown() {
  local i volume keep
  if docker stack ls --format '{{.Name}}' 2>/dev/null | grep -qx day18; then
    docker stack rm day18 >/dev/null
  fi
  docker rm -f day18-sftp day18-rds day18-efs-a day18-efs-b >/dev/null 2>&1 || true
  for i in $(seq 1 90); do
    [ -z "$(docker ps -aq --filter name=day18)" ] && break
    sleep 1
  done
  for i in $(seq 1 30); do
    docker network inspect day18-net >/dev/null 2>&1 || break
    docker network rm day18-net >/dev/null 2>&1 && break
    sleep 1
  done
  for volume in day18-efs day18-wp-efs day18-rds-data day18-caddy-data; do
    keep=no
    for i in "$@"; do [ "$i" = "$volume" ] && keep=yes; done
    [ "$keep" = yes ] && continue
    docker volume inspect "$volume" >/dev/null 2>&1 || continue
    for i in $(seq 1 30); do
      docker volume rm "$volume" >/dev/null 2>&1 && break
      sleep 1
    done
  done
}

#!/usr/bin/env bash
# Day 16 checks. Run after lab.sh.
# Note: this script injects a crash and a freeze on purpose, like the lab, and waits for recovery.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

HTTP=http://localhost:8316
TLS_NAME=day16.test

running() { [ "$(docker container inspect -f '{{.State.Running}}' "$1")" = "true" ]; }
healthy() { [ "$(docker container inspect -f '{{.State.Health.Status}}' "$1")" = "healthy" ]; }
policy() { [ "$(docker container inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$1")" = "unless-stopped" ]; }
poke() { docker exec "$1" node -e "fetch('http://127.0.0.1:3000$2').catch(() => {})" >/dev/null 2>&1; return 0; }
all_healthy() { healthy day16-app-1 && healthy day16-app-2 && healthy day16-app-3 && [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$HTTP/health")" = "200" ]; }
wait_all_healthy() { local _; for _ in $(seq 1 "$1"); do all_healthy && return 0; sleep 1; done; return 1; }
# True when every one of N requests through Caddy answered 200.
all_ok() { local bad; bad=$(seq 1 "$1" | xargs -P 5 -I{} curl -s -o /dev/null -m 10 -w '%{http_code}\n' "$HTTP/" | grep -vc '^200$'); [ "$bad" = "0" ]; }

three_instances() {
  # Caddy's own health check runs every 2 seconds, so after a restart it may need a moment to
  # put an instance back into rotation. Give it up to 60 seconds.
  local attempt request
  for attempt in $(seq 1 60); do
    [ "$(for request in $(seq 1 12); do curl -s -m 5 "$HTTP/"; done | sed -n 's/.*"instance":"\([^"]*\)".*/\1/p' | sort -u | wc -l)" = "3" ] && return 0
    sleep 1
  done
  return 1
}
app_runs_as_non_root() { [ "$(docker exec day16-app-1 id -un)" = "node" ]; }
image_has_healthcheck() { docker image inspect -f '{{json .Config.Healthcheck}}' day16-bad-app | grep -q '/health'; }
published() { docker port day16-caddy-1 "$1/tcp" | grep -q ":$2\$"; }
https_works() { [ "$(curl -sk -o /dev/null -m 8 -w '%{http_code}' --resolve "$TLS_NAME:8317:127.0.0.1" "https://$TLS_NAME:8317/health")" = "200" ]; }
# Capture first, then search: "curl | grep -q" fails under pipefail when grep quits early.
cert_from_caddy_ca() { out=$(curl -skv -m 8 --resolve "$TLS_NAME:8317:127.0.0.1" "https://$TLS_NAME:8317/" 2>&1) && grep -q 'issuer:.*Caddy' <<<"$out"; }
socket_only_in_autoheal() {
  [ "$(docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' day16-autoheal-1)" = "/var/run/docker.sock " ] &&
    ! docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' day16-app-1 day16-app-2 day16-app-3 day16-caddy-1 | grep -q docker.sock
}
crash_is_survived() {
  local before after
  before=$(docker inspect -f '{{.RestartCount}}' day16-app-3)
  poke day16-app-3 /crash
  all_ok 30 || return 1
  wait_all_healthy 60 || return 1
  after=$(docker inspect -f '{{.RestartCount}}' day16-app-3)
  [ "$after" -gt "$before" ]
}
freeze_is_survived_and_healed() {
  poke day16-app-2 /freeze
  all_ok 30 || return 1
  wait_all_healthy 90
}
autoheal_did_restart() { docker compose logs autoheal 2>/dev/null | grep -q 'restarting unhealthy container /day16-app-2'; }

step "Day 16 verification"
# This script crashes and freezes instances, and a freeze takes about 30 seconds to heal. If a
# previous run (or the lab) only just finished, wait for the setup to settle before checking it.
settle_start=$(date +%s)
if wait_all_healthy 90; then
  waited=$(( $(date +%s) - settle_start ))
  [ "$waited" -gt 2 ] && echo "(waited ${waited}s for the instances to recover from the previous run)"
else
  echo "(the instances were still not all healthy after 90 seconds)"
fi
echo "the setup"
check "three app containers are running" bash -c 'for c in day16-app-1 day16-app-2 day16-app-3; do [ "$(docker container inspect -f "{{.State.Running}}" $c)" = true ] || exit 1; done'
check "caddy and autoheal are running" bash -c '[ "$(docker container inspect -f "{{.State.Running}}" day16-caddy-1)" = true ] && [ "$(docker container inspect -f "{{.State.Running}}" day16-autoheal-1)" = true ]'
check "the image has a HEALTHCHECK" image_has_healthcheck
check "the app runs as a non-root user" app_runs_as_non_root
check "all three instances are healthy" all_healthy
check "restart policy is unless-stopped on app, caddy and autoheal" bash -c 'for c in day16-app-1 day16-app-2 day16-app-3 day16-caddy-1 day16-autoheal-1; do [ "$(docker container inspect -f "{{.HostConfig.RestartPolicy.Name}}" $c)" = unless-stopped ] || exit 1; done'
check "host port 8316 maps to Caddy's port 80" published 80 8316
check "host port 8317 maps to Caddy's port 443" published 443 8317
check "only autoheal has the Docker socket" socket_only_in_autoheal
echo "load balancing"
check "twelve requests are answered by all three instances" three_instances
check "HTTPS answers on port 8317 for the name $TLS_NAME" https_works
check "that certificate was issued by Caddy's own authority" cert_from_caddy_ca
echo "failures (these crash and freeze an instance, then wait for recovery)"
check "crash: 30 requests all succeed, the instance is restarted and healthy again" crash_is_survived
check "freeze: 30 requests all succeed and the instance comes back healthy" freeze_is_survived_and_healed
check "autoheal's log shows it restarted the frozen instance" autoheal_did_restart
check "all three instances are healthy at the end" all_healthy
summary

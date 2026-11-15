#!/usr/bin/env bash
# Day 03: what comes back when Docker starts again? (slides 57, 87-88)
#
# A real reboot needs sudo, so this tests the same mechanism without one:
# Docker decides what to start by looking at each container's restart policy
# when the daemon starts. This script runs a throwaway second Docker daemon
# (docker:dind, in the container day03-dind), puts containers with different
# policies in it, then stops that daemon the way a shutdown does, starts it
# again, and looks at what came back. It repeats this with the daemon killed
# instead of stopped, which is what a power cut looks like.
#
# It also reports, for the real daemon, whether Docker itself is enabled at boot
# and which running containers would come back.
#
# The throwaway daemon needs --privileged, so it runs for a few minutes only and
# is removed at the end. Runs on the server; safe to run more than once.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

D=day03-dind
inner() { docker exec "$D" docker "$@"; }
state() { inner inspect -f '{{.State.Status}}' "$1" 2>/dev/null; }
wait_for_daemon() {
  for _ in $(seq 1 60); do
    inner info >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

cleanup() { docker rm -f -v "$D" >/dev/null 2>&1; }
trap cleanup EXIT
cleanup

step "1. The real daemon: is Docker started at boot? (slide 57)"
for unit in docker.service containerd.service; do
  printf '  %-20s %s\n' "$unit" "$(systemctl is-enabled "$unit" 2>&1)"
done
echo "  With the service enabled, systemd starts the daemon at boot, and the daemon then"
echo "  starts every container whose restart policy asks for it."

step "2. The real containers: which would come back after a reboot?"
printf '  %-34s %-16s %s\n' CONTAINER POLICY "COMES BACK?"
stay_down=""
swarm_tasks=0
for name in $(docker ps --format '{{.Names}}' | sort); do
  if [ -n "$(docker inspect -f '{{index .Config.Labels "com.docker.swarm.task.id"}}' "$name")" ]; then
    swarm_tasks=$((swarm_tasks + 1)) # Swarm recreates its own tasks when the daemon starts
    continue
  fi
  policy=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name")
  case $policy in
    always | unless-stopped) back=yes ;;
    on-failure) back="no (only after a failure)"; stay_down="$stay_down $name" ;;
    *) back="no"; stay_down="$stay_down $name" ;;
  esac
  printf '  %-34s %-16s %s\n' "$name" "${policy:-no}" "$back"
done
echo "  Not listed: $swarm_tasks Swarm tasks (days 17, 18). The Swarm manager recreates them when the daemon starts."
echo "  'no' is Docker's default (slide 87). Every lab sets a policy on the containers it leaves running."

step "3. A second Docker daemon to restart safely (docker:dind)"
run docker run -d --privileged --name "$D" -e DOCKER_TLS_CERTDIR= docker:dind
if ! wait_for_daemon; then
  echo "The nested daemon did not start." >&2
  docker logs --tail 20 "$D" >&2
  exit 1
fi
echo "Nested daemon is up: $(inner version --format 'Docker {{.Server.Version}}')"
echo "Copying the nginx image into it (no download):"
docker save nginx | docker exec -i "$D" docker load

step "4. Containers with different restart policies, inside it (slides 87-88)"
run docker exec "$D" docker run -d --name unless-running --restart unless-stopped nginx
run docker exec "$D" docker run -d --name always-running --restart always nginx
run docker exec "$D" docker run -d --name policy-no --restart no nginx
run docker exec "$D" docker run -d --name unless-stopped-by-hand --restart unless-stopped nginx
run docker exec "$D" docker run -d --name always-stopped-by-hand --restart always nginx
echo "Two of them are stopped by hand before the 'reboot' (slide 87):"
run docker exec "$D" docker stop unless-stopped-by-hand always-stopped-by-hand

show() {
  printf '  %-26s %-16s %s\n' CONTAINER POLICY STATE
  for c in unless-running always-running policy-no unless-stopped-by-hand always-stopped-by-hand; do
    printf '  %-26s %-16s %s\n' "$c" "$(inner inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c")" "$(state "$c")"
  done
}
echo
echo "Before:"
show

reboot_round() { # $1 = how the daemon goes down: stop (shutdown) or kill (power cut)
  local how=$1
  case $how in
    stop) run docker stop -t 60 "$D" ;;
    kill) run docker kill "$D" ;;
  esac
  echo "Daemon is down. Everything in it is stopped."
  run docker start "$D"
  wait_for_daemon || echo "The nested daemon did not come back."
  sleep 3
  echo
  echo "After:"
  show
}

step "5. 'Reboot' 1: the daemon is shut down and started again"
reboot_round stop
r1_unless=$(state unless-running)
r1_always=$(state always-running)
r1_no=$(state policy-no)
r1_unless_hand=$(state unless-stopped-by-hand)
r1_always_hand=$(state always-stopped-by-hand)

step "6. 'Reboot' 2: the daemon is killed, as in a power cut"
reboot_round kill
r2_unless=$(state unless-running)
r2_always=$(state always-running)
r2_no=$(state policy-no)
r2_unless_hand=$(state unless-stopped-by-hand)
r2_always_hand=$(state always-stopped-by-hand)

step "7. The page is served again after the restarts"
ok=0
for _ in $(seq 1 10); do
  if inner exec unless-running curl -sf -o /dev/null http://localhost >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 1
done
echo "  unless-running answers HTTP after both restarts: $([ "$ok" = 1 ] && echo yes || echo no)"

step "Results"
PASS=0 FAIL=0
check "Docker is enabled at boot on this machine (docker.service)" systemctl is-enabled docker.service
check "containerd is enabled at boot" systemctl is-enabled containerd.service
check "every running container (Swarm tasks aside) has a policy that brings it back${stay_down:+; missing:$stay_down}" [ -z "$stay_down" ]
check "shutdown: unless-stopped container came back" [ "$r1_unless" = running ]
check "shutdown: always container came back" [ "$r1_always" = running ]
check "shutdown: container with policy 'no' stayed down" [ "$r1_no" != running ]
check "shutdown: unless-stopped container stopped by hand stayed down" [ "$r1_unless_hand" != running ]
check "shutdown: 'always' container stopped by hand came back (slide 87)" [ "$r1_always_hand" = running ]
check "power cut: unless-stopped container came back" [ "$r2_unless" = running ]
check "power cut: always container came back" [ "$r2_always" = running ]
check "power cut: container with policy 'no' stayed down" [ "$r2_no" != running ]
check "power cut: unless-stopped container stopped by hand stayed down" [ "$r2_unless_hand" != running ]
check "power cut: 'always' container stopped by hand came back (slide 87)" [ "$r2_always_hand" = running ]
check "the restarted container serves HTTP" [ "$ok" = 1 ]

cleanup
trap - EXIT
echo
echo "The throwaway daemon has been removed."
summary

#!/usr/bin/env bash
# Day 17 lab: ECS part 1 - task definition, cluster, service (slides 327-337).
# Runs on the server. Docker Swarm stands in for ECS.
# Safe to run more than once: it removes and redeploys its own stack.
#
# Leaves running: the service day17_web (3 tasks, image day17-app:v2) on port 8500.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

service=day17_web
url=http://localhost:8500
work=$PWD/.work

replicas() { docker service ls --filter "name=$service" --format '{{.Replicas}}'; }
wait_replicas() { # wait_replicas N: until N of N tasks are running
  local i
  for i in $(seq 1 90); do
    [ "$(replicas)" = "$1/$1" ] && return 0
    sleep 1
  done
  echo "Timed out waiting for $service to reach $1 running tasks (now: $(replicas))" >&2
  return 1
}
show_tasks() {
  docker service ps "$service" --format 'table {{.ID}}\t{{.Name}}\t{{.Image}}\t{{.DesiredState}}\t{{.CurrentState}}'
}
who_answers() { # N requests -> which tasks answered, with counts
  local i
  for i in $(seq 1 "$1"); do curl -s -m 3 "$url/whoami.php"; done | sort | uniq -c | sed 's/^/  /'
}

rm -rf "$work"
mkdir -p "$work"

# Start clean: remove only this day's stack, and wait until it is really gone.
if docker stack ls --format '{{.Name}}' 2>/dev/null | grep -qx day17; then
  docker stack rm day17 >/dev/null
  for _ in $(seq 1 60); do
    [ -z "$(docker ps -q --filter "name=$service")" ] && [ -z "$(docker network ls -q --filter name=day17_default)" ] && break
    sleep 1
  done
fi

step "1. The image to deploy, in two versions (slide 333: 'what should get executed')"
run docker build -q -t day17-app:v1 --build-arg VERSION=v1 app
run docker build -q -t day17-app:v2 --build-arg VERSION=v2 app

step "2. Create a cluster (slide 336)"
if [ "$(docker info -f '{{.Swarm.LocalNodeState}}')" = "active" ]; then
  echo "This Docker host is already a cluster (swarm mode is active)."
else
  run docker swarm init --advertise-addr 127.0.0.1
fi
echo "The cluster's nodes. ECS on Fargate hides them; here it is the server itself:"
run docker node ls

step "3. The task definition (slide 333)"
echo "stack.yaml describes what to run. Its 'web' entry:"
sed -n '/^services:/,$p' stack.yaml | sed 's/^/  /'

step "4. Create a service: tell the cluster to run the task (slides 332, 337)"
run docker stack deploy --detach=true --resolve-image never -c stack.yaml day17
wait_replicas 2
run docker service ls --filter "name=$service"

step "5. Service, tasks and containers (slides 334, 337)"
echo "The service wants 2 tasks, so the cluster created 2:"
show_tasks
echo
echo "Each task runs as one container on a node:"
for task in $(docker service ps -q --filter desired-state=running "$service"); do
  docker inspect "$task" \
    --format '  task {{.ID}}  ->  container {{printf "%.12s" .Status.ContainerStatus.ContainerID}}'
done
run docker ps --filter "name=$service" --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'

step "6. Requests are spread over the tasks"
echo "12 requests to $url/whoami.php, counted per answering task:"
who_answers 12

step "7. A service is a desired end state: a crashed task is replaced (slide 337)"
victim=$(docker ps -q --filter "name=$service" | head -1)
echo "Killing one task's container, as a crash would:"
run docker kill "$victim"
sleep 2
wait_replicas 2
echo "The service noticed and started a replacement:"
show_tasks

step "8. Scaling: change the desired number of tasks"
run docker service scale --detach "$service=3"
wait_replicas 3
echo "12 requests, counted per answering task:"
who_answers 12

step "9. A new revision, rolled out task by task (slides 333, 337)"
echo "A task definition cannot be changed, only replaced by a new revision. Here the"
echo "new revision is image v2. The service swaps its tasks one at a time while a"
echo "probe keeps requesting the page in the background."
(
  ok=0
  failed=0
  while [ ! -e "$work/stop-probe" ]; do
    if answer=$(curl -fsS -m 2 "$url/whoami.php" 2>/dev/null); then
      ok=$((ok + 1))
      echo "${answer%% *}" >>"$work/probe-versions.log"
    else
      failed=$((failed + 1))
    fi
    sleep 0.2
  done
  echo "$ok $failed" >"$work/probe-result"
) &
probe=$!
run docker service update --detach --image day17-app:v2 "$service"
for _ in $(seq 1 120); do
  [ "$(docker service inspect "$service" -f '{{.UpdateStatus.State}}')" = "completed" ] && break
  sleep 1
done
wait_replicas 3
touch "$work/stop-probe"
wait "$probe"
read -r ok failed <"$work/probe-result"
echo "During the rollout: $ok requests answered, $failed failed."
echo "Versions that answered, in order of first appearance: $(awk '!seen[$0]++' "$work/probe-versions.log" | tr '\n' ' ')"
echo
show_tasks
echo
docker service inspect "$service" \
  --format 'Service now runs:   {{.Spec.TaskTemplate.ContainerSpec.Image}}{{"\n"}}Previous revision:  {{.PreviousSpec.TaskTemplate.ContainerSpec.Image}}{{"\n"}}Rollout state:      {{.UpdateStatus.State}}'

step "Done"
echo "$service keeps running: 3 tasks, image day17-app:v2, port 8500."
echo "Next: setup/run.sh day-17/verify.sh"

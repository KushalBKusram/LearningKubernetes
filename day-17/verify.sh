#!/usr/bin/env bash
# Day 17 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

service=day17_web
url=http://localhost:8500

swarm_active() { [ "$(docker info -f '{{.Swarm.LocalNodeState}} {{.Swarm.ControlAvailable}}')" = "active true" ]; }
has_image() { docker image inspect "$1"; }
replicas_3_of_3() { [ "$(docker service ls --filter "name=$service" --format '{{.Replicas}}')" = "3/3" ]; }
three_containers() { [ "$(docker ps -q --filter "name=$service" | wc -l)" -eq 3 ]; }
all_healthy() { [ "$(docker ps --filter "name=$service" --filter health=healthy -q | wc -l)" -eq 3 ]; }
runs_v2() { docker service inspect "$service" -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' | grep -q '^day17-app:v2'; }
previous_v1() { docker service inspect "$service" -f '{{.PreviousSpec.TaskTemplate.ContainerSpec.Image}}' | grep -q '^day17-app:v1'; }
rollout_completed() { [ "$(docker service inspect "$service" -f '{{.UpdateStatus.State}}')" = "completed" ]; }
page_ok() { [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$url")" = "200" ]; }
answers_v2() { curl -s -m 3 "$url/whoami.php" | grep -q '^v2 '; }
several_tasks_answer() {
  local n
  n=$(for _ in $(seq 1 12); do curl -s -m 3 "$url/whoami.php"; done | sort -u | wc -l)
  [ "$n" -ge 2 ]
}
crashed_task_in_history() { docker service ps "$service" --format '{{.CurrentState}}' | grep -q '^Failed'; }

step "Day 17 verification"
check "this Docker host is a cluster manager (swarm mode active)" swarm_active
check "image present: day17-app:v1" has_image day17-app:v1
check "image present: day17-app:v2" has_image day17-app:v2
check "service $service has 3 of 3 tasks running" replicas_3_of_3
check "each task is one running container (3 containers)" three_containers
check "all 3 containers pass their health check" all_healthy
check "the service runs the new revision (day17-app:v2)" runs_v2
check "the previous revision is still known (day17-app:v1)" previous_v1
check "the rolling update completed" rollout_completed
check "port 8500 answers with 200" page_ok
check "the page is served by version v2" answers_v2
check "requests are answered by more than one task" several_tasks_answer
check "the task history shows the crashed task that was replaced" crashed_task_in_history
summary

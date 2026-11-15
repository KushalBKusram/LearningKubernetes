#!/usr/bin/env bash
# Removes what day 17 created on the server: its stack, its images and its
# scratch folder. Leaves swarm mode only if nothing else uses the cluster
# (day 18 deploys its own stack on it).
set -uo pipefail
cd "$(dirname "$0")"

if docker stack ls --format '{{.Name}}' 2>/dev/null | grep -qx day17; then
  docker stack rm day17 >/dev/null && echo "removed stack day17"
  for _ in $(seq 1 60); do
    [ -z "$(docker ps -q --filter name=day17_web)" ] && [ -z "$(docker network ls -q --filter name=day17_default)" ] && break
    sleep 1
  done
fi

for image in day17-app:v1 day17-app:v2; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    docker image rm "$image" >/dev/null && echo "removed image $image"
  fi
done

rm -rf .work

if [ "$(docker info -f '{{.Swarm.LocalNodeState}}')" = "active" ]; then
  others=$(docker service ls -q | wc -l)
  overlays=$(docker network ls --filter driver=overlay --format '{{.Name}}' | grep -vx ingress | wc -l)
  if [ "$others" -eq 0 ] && [ "$overlays" -eq 0 ]; then
    docker swarm leave --force >/dev/null && echo "left swarm mode: no other services use the cluster"
  else
    echo "kept swarm mode: $others other service(s) and $overlays overlay network(s) still use the cluster"
  fi
fi

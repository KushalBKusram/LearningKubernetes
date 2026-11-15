#!/usr/bin/env bash
# Removes what day 18 created on the server: its stack, the SFTP and database
# containers, its network, volumes (uploads, WordPress, database, certificates),
# images and scratch folder. Leaves swarm mode only if nothing else uses the
# cluster (day 17's service does).
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./common.sh

day18_teardown
echo "removed the day18 stack, containers, network and volumes"

for image in day18-sftp:v1 day18-lb:v1; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    docker image rm "$image" >/dev/null && echo "removed image $image"
  fi
done

rm -rf "$work"

if [ "$(docker info -f '{{.Swarm.LocalNodeState}}')" = "active" ]; then
  others=$(docker service ls -q | wc -l)
  if [ "$others" -eq 0 ]; then
    docker swarm leave --force >/dev/null && echo "left swarm mode: no other services use the cluster"
  else
    echo "kept swarm mode: $others other service(s) still use the cluster"
  fi
fi

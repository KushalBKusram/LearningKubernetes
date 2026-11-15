#!/usr/bin/env bash
# Day 03 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

official_docker() { dpkg -s docker-ce; }
versions_reported() { [ -n "$(docker version --format '{{.Client.Version}}{{.Server.Version}}')" ]; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' day03-apache)" = "true" ]; }
policy_set() { [ "$(docker container inspect -f '{{.HostConfig.RestartPolicy.Name}}' day03-apache)" = "unless-stopped" ]; }
was_restarted() { [ "$(docker container inspect -f '{{.RestartCount}}' day03-apache)" -ge 1 ]; }
serves_page() { curl -s -m 3 http://localhost:8080 | grep -qF 'It works!'; }
enabled_at_boot() { systemctl is-enabled docker.service && systemctl is-enabled containerd.service; }

step "Day 03 verification"
check "Docker comes from Docker's own repository (docker-ce), not the outdated distro package" official_docker
check "client and daemon both report a version" versions_reported
check "day03-apache is running" running
check "restart policy is unless-stopped" policy_set
check "Docker restarted the container after its main process ended" was_restarted
check "Apache serves 'It works!' on port 8080" serves_page
check "Docker and containerd are enabled at boot (what starts the restart-policy containers)" enabled_at_boot
summary

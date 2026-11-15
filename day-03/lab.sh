#!/usr/bin/env bash
# Day 03 lab: Docker on a Linux server (slides 56-97).
# Runs on the server, which stands in for the EC2 instance on the slides.
# Safe to run more than once: it recreates its own container.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

http_status() { curl -s -o /dev/null -m 3 -w '%{http_code}' "$1" || true; }
restart_count() { docker container inspect -f '{{.RestartCount}}' day03-apache; }

docker rm -f day03-apache >/dev/null 2>&1 || true

step "1. The server we are logged in to (slides 62-71)"
echo "Host:   $(hostname)"
echo "OS:     $(. /etc/os-release && echo "$PRETTY_NAME"), $(uname -m)"
echo "User:   $(whoami) (a regular user; root is reached through sudo)"
echo "Groups: $(id -nG)"
if [ -n "${SSH_CONNECTION:-}" ]; then
  echo "SSH:    connected from ${SSH_CONNECTION%% *}, authenticated with a key pair"
fi

step "2. Docker client and Docker daemon (slides 80-83)"
echo "Client version: $(docker version --format '{{.Client.Version}}')"
echo "Daemon version: $(docker version --format '{{.Server.Version}}')"
docker info --format '  The client talks to the daemon, which manages {{.Containers}} containers ({{.ContainersRunning}} running) and {{.Images}} images.'
echo "  Daemon process: $(pgrep -a dockerd | head -1 || echo 'not visible to this user')"

step "3. Apache in a container, restarted automatically (slides 57, 87-88)"
run docker run -d --name day03-apache -p 8080:80 --restart unless-stopped httpd
sleep 1
echo "Restart policy: $(docker container inspect -f '{{.HostConfig.RestartPolicy.Name}}' day03-apache)"
echo "HTTP status of http://localhost:8080 -> $(http_status http://localhost:8080)"

step "4. The policy at work: end Apache's main process"
echo "Restarts so far: $(restart_count)"
run docker exec day03-apache bash -c 'kill 1' || true
echo "Apache has been told to shut down. Waiting for Docker to bring the container back..."
for _ in $(seq 1 20); do
  [ "$(restart_count)" -ge 1 ] && [ "$(http_status http://localhost:8080)" = "200" ] && break
  sleep 1
done
echo "Restarts now:    $(restart_count)"
echo "HTTP status of http://localhost:8080 -> $(http_status http://localhost:8080)"

step "5. Setting the policy on an existing container (slide 88)"
if docker container inspect day02-nginx >/dev/null 2>&1; then
  echo "day02-nginx policy before: $(docker container inspect -f '{{.HostConfig.RestartPolicy.Name}}' day02-nginx)"
  run docker update --restart unless-stopped day02-nginx
  echo "day02-nginx policy after:  $(docker container inspect -f '{{.HostConfig.RestartPolicy.Name}}' day02-nginx)"
else
  echo "day02-nginx does not exist, skipping. The command would be:"
  echo "  docker update --restart unless-stopped <container>"
fi

step "Done"
echo "day03-apache keeps running on port 8080 and will come back after a reboot."
echo "With 'unless-stopped', 'docker stop day03-apache' keeps it stopped, also across reboots."
echo "Next: setup/run.sh day-03/verify.sh"

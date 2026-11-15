#!/usr/bin/env bash
# Day 01 lab: first containers, images and tags (slides 1-24).
# Runs on the server. Safe to run more than once.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

step "1. Does Docker work? (slide 10)"
run docker run --rm hello-world

step "2. Other operating systems in containers (slides 6, 10)"
echo "Host:             $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "ubuntu container: $(docker run --rm ubuntu sh -c '. /etc/os-release && echo "$PRETTY_NAME"')"
echo "fedora container: $(docker run --rm fedora sh -c '. /etc/os-release && echo "$PRETTY_NAME"')"
echo
echo "The userland differs, but every container shares the host's kernel:"
echo "Host kernel:      $(uname -r)"
echo "fedora container: $(docker run --rm fedora uname -r)"

step "3. Images come from a registry: Docker Hub (slides 12, 15)"
run docker image pull python:slim

step "4. Tags select versions (slide 17)"
echo "python (same as python:latest): $(docker run --rm python python --version)"
echo "python:slim:                    $(docker run --rm python:slim python --version)"
echo "python:3.12-slim:               $(docker run --rm python:3.12-slim python --version)"
echo "node:                           $(docker run --rm node node --version)"

step "5. Looking at images (slide 15)"
run docker image ls
run docker image history python:slim
echo
echo "A few fields from 'docker image inspect python:slim':"
docker image inspect python:slim \
  --format '  architecture: {{.Architecture}}{{"\n"}}  os:           {{.Os}}{{"\n"}}  layers:       {{len .RootFS.Layers}}{{"\n"}}  default cmd:  {{.Config.Cmd}}'

step "6. A container can never alter its image (slide 14)"
docker rm -f day01-scratch >/dev/null 2>&1 || true
run docker run --name day01-scratch ubuntu sh -c 'echo "written inside the container" > /note.txt && cat /note.txt'
echo "A second container from the same image does not have that file:"
if docker run --rm ubuntu cat /note.txt 2>/dev/null; then
  echo "UNEXPECTED: the file exists in a fresh container"
else
  echo "  /note.txt: not found (expected). The file lived only in the first container's writable layer."
fi
docker rm day01-scratch >/dev/null

step "7. docker run = pull + create + start (slide 19)"
docker rm -f day01-steps >/dev/null 2>&1 || true
run docker image pull ubuntu
run docker container create --name day01-steps ubuntu echo "created first, started second"
run docker container start -a day01-steps
docker rm day01-steps >/dev/null

step "Done"
echo "Next: setup/run.sh day-01/verify.sh"

#!/usr/bin/env bash
# Day 02 checks. Run after lab.sh and exercise.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

running() { [ "$(docker container inspect -f '{{.State.Running}}' day02-nginx)" = "true" ]; }
port_mapped() { docker port day02-nginx 80/tcp | grep -q ':8888$'; }
serves_http() { [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://localhost:8888)" = "200" ]; }
page_has() { curl -s -m 3 http://localhost:8888 | grep -qF "$1"; }
temp_gone() { [ -z "$(docker container ls -aq --filter name=day02-python --filter name=day02-created --filter name=day02-hidden)" ]; }

step "Day 02 verification"
check "day02-nginx is running" running
check "host port 8888 is mapped to container port 80" port_mapped
check "http://localhost:8888 answers with 200" serves_http
check "exercise: background is lightgray" page_has 'background-color: lightgray'
check "exercise: heading says 'Welcome to nginx in docker'" page_has '<h1>Welcome to nginx in docker</h1>'
check "temporary containers were removed" temp_gone
summary

#!/usr/bin/env bash
# Day 02 lab: managing containers, running nginx (slides 25-55).
# Runs on the server. Safe to run more than once: it recreates its own containers.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

# Start clean: remove only the containers this lab creates.
docker rm -f day02-hidden day02-nginx day02-python day02-created >/dev/null 2>&1 || true

http_status() { curl -s -o /dev/null -m 3 -w '%{http_code}' "$1" || true; }

step "1. nginx without a published port (slides 32-33)"
run docker run -d --name day02-hidden nginx
sleep 1
echo "Port mappings of day02-hidden: '$(docker port day02-hidden)' (none)"
echo "The container listens on port 80 inside its own isolated network, but nothing on the host maps to it."
docker rm -f day02-hidden >/dev/null

step "2. Publish a port, run detached, give it a name (slides 34-41)"
run docker run -d --name day02-nginx -p 8888:80 nginx
sleep 1
run docker port day02-nginx
echo "HTTP status of http://localhost:8888 -> $(http_status http://localhost:8888)"

step "3. Information about containers (slide 39)"
run docker container ls -as
run docker container stats --no-stream
echo
echo "A few fields from 'docker container inspect day02-nginx':"
docker container inspect day02-nginx \
  --format '  status:  {{.State.Status}}{{"\n"}}  image:   {{.Config.Image}}{{"\n"}}  ip:      {{.NetworkSettings.Networks.bridge.IPAddress}}{{"\n"}}  command: {{.Path}} {{.Args}}'

step "4. Logs of a detached container (slide 36)"
run docker logs --tail 5 day02-nginx

step "5. Stop and start (slide 43)"
run docker stop day02-nginx
echo "HTTP status while stopped -> '$(http_status http://localhost:8888)' (no answer)"
run docker start day02-nginx
sleep 1
echo "HTTP status after start   -> $(http_status http://localhost:8888)"

step "6. docker run always creates a new container; --rm deletes it afterwards (slides 46-47)"
before=$(docker container ls -aq | wc -l)
run docker run --rm ubuntu echo "first throwaway container"
run docker run --rm fedora echo "second throwaway container"
after=$(docker container ls -aq | wc -l)
echo "Containers before: $before, after: $after (unchanged, because of --rm)"

step "7. Changing the program a container starts (slide 49)"
echo "python's default program is the Python shell. Here it is replaced with bash, which installs NumPy and then runs python:"
run docker run --rm python:slim bash -c 'pip install -q --root-user-action=ignore numpy && python -c "import numpy; print(\"NumPy\", numpy.__version__)"'

step "8. Running an extra program in a running container: docker exec (slide 51)"
run docker run -d -it --name day02-python python:slim
run docker exec day02-python pip install -q --root-user-action=ignore numpy
run docker exec day02-python python -c 'import numpy; print("NumPy", numpy.__version__, "installed via exec")'

step "9. docker create: configure first, start later (slide 53)"
run docker create --name day02-created -p 8889:80 nginx
echo "State after create: $(docker container inspect -f '{{.State.Status}}' day02-created)"
run docker start day02-created
sleep 1
echo "HTTP status of http://localhost:8889 -> $(http_status http://localhost:8889)"
echo "The port mapping was fixed at creation and cannot be changed on this container."

step "10. Delete containers (slide 44)"
echo "A running container cannot be removed:"
docker rm day02-created 2>&1 | sed 's/^/  /' || true
run docker stop day02-created
run docker rm day02-created
run docker rm -f day02-python

step "Done"
echo "day02-nginx is still running on port 8888 for the exercise."
echo "Next: setup/run.sh day-02/exercise.sh, then setup/run.sh day-02/verify.sh"

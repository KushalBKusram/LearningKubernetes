#!/usr/bin/env bash
# Day 15 lab: Docker Compose (slides 301-315).
# Runs on the server. Safe to run more than once: it starts from scratch each time.
#
# Leaves running the compose project "day15":
#   db          MariaDB 10.11, data on volume day15-db-data
#   wordpress   WordPress, port 8325, files on volume day15-wp-data
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

dc() { docker compose "$@"; }
sql() { dc exec -T db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" --table -e "$1"' sh "$1"; }
http_code() { curl -s -o /dev/null -m 5 -w '%{http_code}' "$1" || true; }
wait_healthy() { # wait_healthy <service> <seconds>
  local _ id
  for _ in $(seq 1 "$2"); do
    id=$(dc ps -q "$1" 2>/dev/null || true)
    [ -n "$id" ] && [ "$(docker inspect -f '{{.State.Health.Status}}' "$id" 2>/dev/null)" = "healthy" ] && return 0
    sleep 1
  done
  echo "$1 did not become healthy" >&2
  dc logs --tail 20 "$1" >&2
  return 1
}

# Start clean: take down only this project, including its volumes.
dc down --volumes --remove-orphans >/dev/null 2>&1 || true

step "1. Passwords live in .env, not in compose.yaml (slide 313)"
# A random password for each run, readable only by you. .env is listed in .gitignore.
(umask 077 && cat >.env <<EOF
DB_ROOT_PASSWORD=$(openssl rand -hex 12)
DB_PASSWORD=$(openssl rand -hex 12)
DB_NAME=wordpress
DB_USER=wordpress
WP_PORT=8325
EOF
)
echo ".env written with random passwords (names only shown): $(cut -d= -f1 .env | tr '\n' ' ')"
echo "compose.yaml refers to them as \${DB_PASSWORD} and so on. Password values in compose.yaml: $(grep -cE 'MARIADB_.*PASSWORD: [^$]' compose.yaml || true)"
echo "Without .env the file refuses to start, thanks to the \${VAR:?message} syntax:"
if out=$(dc --env-file /dev/null config 2>&1); then
  echo "  UNEXPECTED: it started without .env"
else
  echo "$out" | head -1 | sed 's/^/  /'
fi

step "2. The file describes what several 'docker run' commands would do (slides 304-305, 309)"
run docker compose config --services
echo "Validate the file:"
run docker compose config --quiet

step "3. docker compose up --detach (slides 305, 311, 315)"
run docker compose up --detach
echo "The db healthcheck gates WordPress (depends_on, service_healthy). Waiting for both to be healthy..."
wait_healthy db 120
wait_healthy wordpress 120
run docker compose ps
echo "Compose created a private network for the project and put both containers in it:"
run docker network ls --filter name=day15-net
echo "WordPress reaches the database by its service name 'db'. In the WordPress container:"
run docker compose exec -T wordpress getent hosts db
echo "http://localhost:8325 -> HTTP $(http_code http://localhost:8325)"
echo "(the first answer is a redirect to the WordPress install page, which is where a fresh site starts)"
echo "Final page: $(curl -s -L -m 10 http://localhost:8325 | grep -o -m1 '<title>[^<]*</title>')"

step "4. Data in the database, then a restart cycle (slide 311: stop, start, pause, unpause)"
sql "CREATE TABLE wordpress.day15_notes (id INT PRIMARY KEY AUTO_INCREMENT, note VARCHAR(100));
     INSERT INTO wordpress.day15_notes (note) VALUES ('written before stop'), ('written before down');"
sql 'SELECT * FROM wordpress.day15_notes'
run docker compose stop
run docker compose ps --all --format 'table {{.Service}}\t{{.State}}'
run docker compose start
wait_healthy db 60
wait_healthy wordpress 60
echo "pause freezes the processes without stopping the containers:"
run docker compose pause wordpress
echo "  http://localhost:8325 while paused -> HTTP '$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://localhost:8325 || true)' (no answer)"
run docker compose unpause wordpress
sleep 1
echo "  http://localhost:8325 after unpause -> HTTP $(http_code http://localhost:8325)"

step "5. down removes containers and the network, but volumes remain (slide 311)"
run docker compose down
echo "Containers left in the project: $(dc ps --all -q | wc -l)"
run docker volume ls --filter name=day15-
run docker compose up --detach
wait_healthy db 120
wait_healthy wordpress 120
echo "A new database container on the old volume still has the rows:"
sql 'SELECT * FROM wordpress.day15_notes'

step "6. Logs and a one-off command (slide 311)"
run docker compose logs --tail 3 db
run docker compose exec -T db sh -c 'mariadb --version'

step "Done"
echo "WordPress: http://$(public_name):8325"
echo "Next: setup/run.sh day-15/verify.sh"

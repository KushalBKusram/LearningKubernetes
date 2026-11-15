#!/usr/bin/env bash
# Day 15 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

dc() { docker compose "$@"; }
health_of() { docker inspect -f '{{.State.Health.Status}}' "$(dc ps -q "$1")"; }
query() { dc exec -T db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -B -e "$1"' sh "$1"; }

file_is_valid() { dc config --quiet; }
no_secrets_in_file() { ! grep -qE '(PASSWORD):[[:space:]]+[^$[:space:]]' compose.yaml; }
env_ignored() { grep -qxF '.env' .gitignore; }
env_private() { [ "$(stat -c %a .env)" = "600" ]; }
env_required() { ! dc --env-file /dev/null config; }
two_services() { [ "$(dc ps -q | wc -l)" = "2" ]; }
db_healthy() { [ "$(health_of db)" = "healthy" ]; }
wp_healthy() { [ "$(health_of wordpress)" = "healthy" ]; }
wp_waits_for_db() { dc config | grep -A2 'depends_on:' | grep -q 'condition: service_healthy'; }
wp_answers() { [ "$(curl -s -L -o /dev/null -m 10 -w '%{http_code}' http://localhost:8325)" = "200" ]; }
# Fetch first, then search: "curl | grep -q" fails under pipefail when grep quits early.
wp_install_page() { page=$(curl -s -L -m 10 http://localhost:8325) && grep -qi 'WordPress' <<<"$page"; }
same_network() { [ "$(docker network inspect -f '{{len .Containers}}' day15-net)" = "2" ]; }
db_by_name() { dc exec -T wordpress getent hosts db; }
db_not_published() { [ -z "$(docker port "$(dc ps -q db)")" ]; }
rows_survived_down() { [ "$(query 'SELECT COUNT(*) FROM wordpress.day15_notes')" = "2" ]; }
volumes_exist() { docker volume inspect day15-db-data day15-wp-data; }
wp_reaches_db_with_credentials() {
  dc exec -T wordpress bash -c 'exec 3<>/dev/tcp/db/3306'
}

step "Day 15 verification"
echo "the file and .env"
check "compose.yaml is valid" file_is_valid
check "compose.yaml contains no password values" no_secrets_in_file
check ".env is listed in .gitignore" env_ignored
check ".env is readable only by its owner" env_private
check "starting without .env is refused" env_required
echo "the running project"
check "two containers in the project" two_services
check "the db container is healthy" db_healthy
check "the wordpress container is healthy" wp_healthy
check "wordpress is set to wait for a healthy db" wp_waits_for_db
check "both containers are on the network day15-net" same_network
check "wordpress resolves the name 'db'" db_by_name
check "wordpress can open a connection to db:3306" wp_reaches_db_with_credentials
check "the database publishes no port to the host" db_not_published
check "http://localhost:8325 ends in a 200 page" wp_answers
check "that page is WordPress" wp_install_page
echo "volumes and 'down'"
check "volumes day15-db-data and day15-wp-data exist" volumes_exist
check "rows written before 'docker compose down' are still there" rows_survived_down
summary

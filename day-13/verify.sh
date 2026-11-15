#!/usr/bin/env bash
# Day 13 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

html=/usr/share/nginx/html

query() {
  docker exec day13-mariadb sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -B -e "$1"' sh "$1"
}
mount_of() { docker inspect -f '{{range .Mounts}}{{.Type}}:{{.Name}}:{{.Destination}}{{end}}' "$1"; }

running() { [ "$(docker container inspect -f '{{.State.Running}}' "$1")" = "true" ]; }
nginx_on_volume() { [ "$(mount_of day13-nginx)" = "volume:day13-nginx-vol:$html" ]; }
file_from_other_container() { curl -s -m 3 http://localhost:8313/hello.txt | grep -qF 'stored on a volume, not in a container'; }
db_on_volume() { [ "$(mount_of day13-mariadb)" = "volume:day13-mariadb-vol:/var/lib/mysql" ]; }
db_is_new_image() { [ "$(docker container inspect -f '{{.Config.Image}}' day13-mariadb)" = "mariadb:latest" ]; }
db_not_old_version() { v=$(query 'SELECT VERSION()') && [ -n "$v" ] && [ "${v#10.11.}" = "$v" ]; }
rows_survived() { [ "$(query 'SELECT COUNT(*) FROM course.notes')" = "3" ]; }
rows_from_old_version() { [ "$(query "SELECT COUNT(*) FROM course.notes WHERE written_with LIKE '10.11.%'")" = "3" ]; }
image_declares_volume() { docker image inspect -f '{{json .Config.Volumes}}' day13-volume-demo | grep -qF "$html"; }
temp_gone() {
  [ -z "$(docker container ls -aq --filter name=day13-anon --filter name=day13-declared)" ] &&
    ! docker volume inspect day13-auto-vol
}

step "Day 13 verification"
echo "named volume shared by containers"
check "day13-nginx is running" running day13-nginx
check "day13-nginx serves from the volume day13-nginx-vol" nginx_on_volume
check "a file written through another container is served on port 8313" file_from_other_container
echo "database update"
check "day13-mariadb is running" running day13-mariadb
check "its data directory is the volume day13-mariadb-vol" db_on_volume
check "it runs the newest image (mariadb:latest)" db_is_new_image
check "the server version is no longer 10.11" db_not_old_version
check "all 3 rows survived the update" rows_survived
check "the rows were written by the old version (10.11)" rows_from_old_version
echo "other"
check "the image day13-volume-demo declares a VOLUME" image_declares_volume
check "temporary containers and volumes were removed" temp_gone
summary

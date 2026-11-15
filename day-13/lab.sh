#!/usr/bin/env bash
# Day 13 lab: volumes (slides 265-281).
# Runs on the server. Safe to run more than once: it starts from scratch each time.
#
# Leaves running:
#   day13-nginx    port 8313   serves files from the volume day13-nginx-vol
#   day13-mariadb  no port     newest MariaDB, data on the volume day13-mariadb-vol
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

html=/usr/share/nginx/html
work=$PWD/.work # scratch space on the server, recreated on every run
OLD_IMAGE=mariadb:10.11
NEW_IMAGE=mariadb:latest

# Run SQL as root inside the database container. The password never leaves the container.
sql() {
  docker exec day13-mariadb sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" --table -e "$1"' sh "$1"
}
# The server is ready once it listens on the network port (the setup phase logs "port: 0").
wait_for_db() {
  local _
  for _ in $(seq 1 120); do
    if docker logs day13-mariadb 2>&1 | grep -q 'port: 3306' && sql 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "MariaDB did not become ready. Last log lines:" >&2
  docker logs --tail 20 day13-mariadb >&2
  return 1
}

# Start clean: remove only what this lab creates.
docker rm -f -v day13-nginx day13-anon day13-declared day13-mariadb >/dev/null 2>&1 || true
docker volume rm day13-nginx-vol day13-auto-vol day13-mariadb-vol >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$work"

# A throwaway root password for this lab database, kept out of the command lines below.
(umask 077 && echo "MARIADB_ROOT_PASSWORD=$(openssl rand -hex 12)" >"$work/db.env")

step "1. Create and inspect a volume (slide 271)"
run docker volume create day13-nginx-vol
run docker volume ls --filter name=day13-
run docker volume inspect day13-nginx-vol --format '  driver: {{.Driver}}{{"\n"}}  stored at: {{.Mountpoint}}'
echo "Docker manages that directory. We only reach it through 'docker volume' and containers (slide 270)."

step "2. Connect a volume with --mount (slide 273)"
run docker run -d --restart unless-stopped --name day13-nginx -p 8313:80 --mount "type=volume,source=day13-nginx-vol,destination=$html" nginx
sleep 1
echo "The volume was empty, so Docker filled it with what the image has at that path:"
run docker run --rm -v day13-nginx-vol:/site ubuntu ls /site

step "3. One volume, several containers, connected with -v (slides 270, 274)"
run docker run --rm -v day13-nginx-vol:/site ubuntu sh -c 'echo "stored on a volume, not in a container" > /site/hello.txt'
echo "nginx serves the file the other container wrote:"
echo "  http://localhost:8313/hello.txt -> $(curl -s -m 3 http://localhost:8313/hello.txt)"

step "4. The data outlives the container (slide 268: containers are replaced, not updated)"
run docker rm -f day13-nginx
run docker volume ls --filter name=day13-nginx-vol
run docker run -d --restart unless-stopped --name day13-nginx -p 8313:80 -v "day13-nginx-vol:$html" nginx
sleep 1
echo "A brand-new container, the same file:"
echo "  http://localhost:8313/hello.txt -> $(curl -s -m 3 http://localhost:8313/hello.txt)"

step "5. A volume that is in use cannot be deleted (slide 271)"
if out=$(docker volume rm day13-nginx-vol 2>&1); then
  echo "  UNEXPECTED: the volume was removed"
else
  echo "  $out"
fi

step "6. -v with a name creates a volume; -v with a path starting with / is a bind mount (slide 274)"
run docker run --rm -v day13-auto-vol:/data ubuntu sh -c 'echo created > /data/file.txt'
echo "day13-auto-vol did not exist. Docker created it:"
run docker volume ls --filter name=day13-auto-vol
run docker volume rm day13-auto-vol

step "7. Volumes that images create automatically (slide 276)"
run docker run -d --name day13-anon --env-file "$work/db.env" "$OLD_IMAGE"
run docker inspect -f '{{ .Mounts }}' day13-anon
anon=$(docker inspect -f '{{range .Mounts}}{{.Name}}{{end}}' day13-anon)
echo "No -v was given, yet the database files are on a volume with a generated name:"
run docker volume ls --filter "name=$anon"
echo "Hard to find again later. Naming the volume ourselves is better (next steps)."
run docker rm -f -v day13-anon

step "8. VOLUME in a Dockerfile (slide 278)"
run cat volume-demo/Dockerfile
run docker build -q -t day13-volume-demo volume-demo
echo "The image now declares: $(docker image inspect -f '{{json .Config.Volumes}}' day13-volume-demo)"
run docker run -d --name day13-declared day13-volume-demo
docker inspect -f '{{range .Mounts}}  type={{.Type}}  {{.Destination}}  (volume {{printf "%.12s" .Name}}...){{"\n"}}{{end}}' day13-declared
run docker rm -f -v day13-declared

step "9. The plan of attack: an outdated MariaDB on a named volume (slides 276, 281)"
run docker run -d --restart unless-stopped --name day13-mariadb -v day13-mariadb-vol:/var/lib/mysql --env-file "$work/db.env" "$OLD_IMAGE"
wait_for_db
sql 'SELECT VERSION() AS running_version'
echo "Insert some data:"
sql "CREATE DATABASE course;
     CREATE TABLE course.notes (id INT PRIMARY KEY AUTO_INCREMENT, note VARCHAR(100), written_with VARCHAR(40));
     INSERT INTO course.notes (note, written_with) VALUES
       ('volumes keep data outside the container', VERSION()),
       ('containers are replaced, not updated', VERSION()),
       ('this row must survive the update', VERSION());"
sql 'SELECT * FROM course.notes'

step "10. Update the database: throw the container away, start a newer one on the same volume (slide 280)"
run docker stop day13-mariadb
run docker rm day13-mariadb
run docker run -d --restart unless-stopped --name day13-mariadb -v day13-mariadb-vol:/var/lib/mysql --env-file "$work/db.env" -e MARIADB_AUTO_UPGRADE=1 "$NEW_IMAGE"
wait_for_db
sql 'SELECT VERSION() AS running_version'
echo "The data written by the old version is still there:"
sql 'SELECT * FROM course.notes'

step "Done"
echo "day13-nginx    http://localhost:8313/hello.txt  (volume day13-nginx-vol)"
echo "day13-mariadb  newest MariaDB on volume day13-mariadb-vol"
echo "Next: setup/run.sh day-13/verify.sh"

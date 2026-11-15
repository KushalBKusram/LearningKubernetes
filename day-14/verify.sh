#!/usr/bin/env bash
# Day 14 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

running() { [ "$(docker container inspect -f '{{.State.Running}}' "$1")" = "true" ]; }
networks_of() { docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' "$1"; }
probe() { docker run --rm --network "$1" ubuntu bash -c "$2"; }

only_custom_network() { [ "$(networks_of "$1")" = "day14-mongo-net " ]; }
express_resolves_mongo() { docker exec day14-express getent hosts day14-mongo; }
# The mongo image also declares /data/configdb as a volume, so look for our mount among the list.
mongo_has_volume() { docker inspect -f '{{range .Mounts}}{{.Type}}:{{.Name}}:{{.Destination}}{{"\n"}}{{end}}' day14-mongo | grep -qxF 'volume:day14-mongo-vol:/data/db'; }
mongo_unpublished() { [ -z "$(docker port day14-mongo)" ]; }
mongo_has_data() { docker exec day14-mongo mongosh --quiet --eval 'quit(db.getSiblingDB("course").notes.countDocuments() >= 1 ? 0 : 1)'; }
express_published() { docker port day14-express 8081/tcp | grep -q ':8314$'; }
express_serves() { [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://localhost:8314)" = "200" ]; }
express_sees_db() { curl -s -m 5 http://localhost:8314 | grep -qF 'course'; }
name_resolves_on_custom() { probe day14-mongo-net 'getent hosts day14-mongo'; }
name_fails_on_bridge() { ! probe bridge 'getent hosts day14-mongo'; }
mongo_unreachable_from_bridge() {
  ip=$(docker inspect -f '{{(index .NetworkSettings.Networks "day14-mongo-net").IPAddress}}' day14-mongo)
  ! docker run --rm ubuntu bash -c "timeout 3 bash -c 'exec 3<>/dev/tcp/$ip/27017'"
}
none_has_only_loopback() { [ "$(docker run --rm --network none ubuntu ls /sys/class/net)" = "lo" ]; }
default_networks_exist() { docker network inspect bridge host none; }
temp_gone() {
  [ -z "$(docker container ls -aq --filter name=day14-a --filter name=day14-b --filter name=day14-host --filter name=day14-none)" ] &&
    ! docker network inspect day14-net && ! docker network inspect day14-other
}

step "Day 14 verification"
echo "the default networks"
check "bridge, host and none exist" default_networks_exist
check "a container with --network none has only the loopback interface" none_has_only_loopback
echo "MongoDB + mongo-express on a custom network"
check "day14-mongo is running" running day14-mongo
check "day14-mongo is only on day14-mongo-net" only_custom_network day14-mongo
check "day14-mongo keeps its data on the volume day14-mongo-vol" mongo_has_volume
check "day14-mongo publishes no port" mongo_unpublished
check "the database holds the document the lab inserted" mongo_has_data
check "day14-express is running" running day14-express
check "day14-express is only on day14-mongo-net" only_custom_network day14-express
check "day14-express maps host port 8314 to its port 8081" express_published
check "http://localhost:8314 answers with 200" express_serves
check "mongo-express lists the database 'course', so it reached MongoDB" express_sees_db
echo "names and isolation"
check "day14-express resolves 'day14-mongo' by name" express_resolves_mongo
check "another container on day14-mongo-net resolves the name too" name_resolves_on_custom
check "a container on the default bridge cannot resolve the name" name_fails_on_bridge
check "a container on the default bridge cannot reach MongoDB's port" mongo_unreachable_from_bridge
check "temporary containers and networks were removed" temp_gone
summary

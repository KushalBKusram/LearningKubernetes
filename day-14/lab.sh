#!/usr/bin/env bash
# Day 14 lab: Docker networking (slides 282-300).
# Runs on the server. Safe to run more than once: it starts from scratch each time.
#
# Leaves running:
#   day14-mongo-net   custom bridge network
#   day14-mongo       MongoDB, data on the volume day14-mongo-vol, no published port
#   day14-express     mongo-express, published on port 8314
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

work=$PWD/.work # scratch space on the server, recreated on every run
SMALL=nginx  # a small web server to put on the networks
PROBE=ubuntu # a throwaway container to test from

# Run a bash command in a throwaway container attached to the given network.
# The ubuntu image has no ping or curl, so the probes use getent and bash's /dev/tcp.
probe() {
  local net=$1
  shift
  docker run --rm --network "$net" "$PROBE" bash -c "$*"
}

docker rm -f -v day14-a day14-b day14-c day14-host day14-none day14-mongo day14-express >/dev/null 2>&1 || true
docker network rm day14-net day14-other day14-mongo-net >/dev/null 2>&1 || true
docker volume rm day14-mongo-vol >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$work"

step "1. The default networks (slides 286, 288)"
run docker network ls --filter type=builtin
run docker network inspect bridge --format '  subnet {{(index .IPAM.Config 0).Subnet}}, gateway {{(index .IPAM.Config 0).Gateway}}'

step "2. Default bridge: containers reach each other by IP address, not by name (slides 288, 296)"
run docker run -d --name day14-a "$SMALL"
run docker run -d --name day14-b "$SMALL"
ip_a=$(docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' day14-a)
echo "day14-a has the address $ip_a"
echo "A third container on the default bridge, reaching day14-a by IP address:"
probe bridge "exec 3<>/dev/tcp/$ip_a/80 && printf 'GET / HTTP/1.0\r\n\r\n' >&3 && head -1 <&3"
echo "The same container, reaching day14-a by name:"
probe bridge 'getent hosts day14-a || echo "  the name day14-a does not resolve (expected)"'
run docker rm -f day14-a day14-b

step "3. Custom bridge network: names resolve to addresses (slides 293, 296)"
run docker network create day14-net
run docker run -d --network day14-net --name day14-a "$SMALL"
run docker run -d --network day14-net --name day14-b "$SMALL"
echo "From a third container on the same network, by name:"
probe day14-net 'getent hosts day14-a day14-b'
echo "A bash /dev/tcp connection to day14-a on port 80:"
probe day14-net 'exec 3<>/dev/tcp/day14-a/80 && printf "GET / HTTP/1.0\r\n\r\n" >&3 && head -1 <&3'

step "4. Isolation: another network cannot reach it (slide 293)"
run docker network create day14-other
echo "From day14-other, day14-a does not even resolve:"
probe day14-other 'getent hosts day14-a || echo "  day14-a: not found (expected)"'

step "5. Connect and disconnect a running container (slide 294)"
run docker network connect day14-other day14-a
echo "day14-a is now on both networks:"
docker inspect -f '  {{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' day14-a
echo "Now day14-other can resolve it:"
probe day14-other 'getent hosts day14-a'
run docker network disconnect day14-other day14-a
echo "Disconnected again:"
docker inspect -f '  {{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' day14-a
run docker rm -f day14-a day14-b
run docker network rm day14-net day14-other

step "6. The host network: no isolation, no port publishing (slide 290)"
echo "nginx normally listens on port 80, which another day uses on this machine. With the host"
echo "network the port is the host's own, so a config file moves nginx to port 8315:"
cat >"$work/host.conf" <<'EOF'
server {
    listen 8315;
    location / { return 200 "served from the host network\n"; }
}
EOF
run docker run -d --name day14-host --network host -v "$work/host.conf:/etc/nginx/conf.d/default.conf:ro" "$SMALL"
sleep 1
echo "No -p was given, yet the port is open on the server itself:"
echo "  http://localhost:8315 -> $(curl -s -m 3 http://localhost:8315 || true)"
host_ifaces=$(ls /sys/class/net | grep -vE '^veth' | tr '\n' ' ')
cont_ifaces=$(docker exec day14-host ls /sys/class/net | grep -vE '^veth' | tr '\n' ' ')
echo "Its network namespace is the host's: it sees the server's own interfaces (virtual veth ones left out):"
echo "  on the host:        $host_ifaces"
echo "  inside the container: $cont_ifaces"
[ "$host_ifaces" = "$cont_ifaces" ] && echo "  identical, so there is no network isolation."
run docker rm -f day14-host

step "7. The none network: loopback only (slide 291)"
run docker run -d --name day14-none --network none "$SMALL"
echo "Interfaces inside: $(docker exec day14-none ls /sys/class/net | tr '\n' ' ')"
echo "Reaching the internet from inside:"
if docker run --rm --network none "$PROBE" bash -c 'exec 3<>/dev/tcp/1.1.1.1/53' 2>/dev/null; then
  echo "  UNEXPECTED: connected"
else
  echo "  no route (expected)"
fi
run docker rm -f day14-none

step "8. Task part 1: MongoDB on its own network with a volume (slides 298-299)"
run docker network create day14-mongo-net
run docker run -d --restart unless-stopped --name day14-mongo --network day14-mongo-net --mount type=volume,source=day14-mongo-vol,destination=/data/db mongo
echo "No -p: nothing outside the network can reach the database. A command in it shows the OS it runs on (the tip on slide 299):"
run docker exec day14-mongo sh -c '. /etc/os-release && echo "  $PRETTY_NAME"'
for _ in $(seq 1 60); do
  docker exec day14-mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1 && break
  sleep 1
done
docker exec day14-mongo mongosh --quiet --eval 'db.getSiblingDB("course").notes.insertOne({note:"stored by the day 14 lab"}); print("inserted; documents in course.notes: " + db.getSiblingDB("course").notes.countDocuments())'

step "9. Task part 2: mongo-express, attached to the network, port 8081 published as 8314 (slide 300)"
run docker run -d --restart unless-stopped --name day14-express --network day14-mongo-net -p 8314:8081 \
  -e ME_CONFIG_MONGODB_URL=mongodb://day14-mongo:27017 \
  -e ME_CONFIG_BASICAUTH=false \
  mongo-express
echo "mongo-express finds the database by its container name, day14-mongo, which only works on a custom network."
for _ in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://localhost:8314 || true)" = "200" ] && break
  sleep 1
done
echo "  http://localhost:8314 -> HTTP $(curl -s -o /dev/null -m 3 -w '%{http_code}' http://localhost:8314 || true)"
curl -s -m 5 http://localhost:8314 | grep -o -m1 'course' | head -1 | sed 's/^/  the database list includes: /' || true

step "Done"
echo "day14-mongo     MongoDB on network day14-mongo-net, volume day14-mongo-vol"
echo "day14-express   http://$(public_name):8314"
echo "Next: setup/run.sh day-14/verify.sh"

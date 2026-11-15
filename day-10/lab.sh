#!/usr/bin/env bash
# Day 10 lab: smaller, safer images (slides 216-231).
# Runs on the server. Safe to run more than once: it recreates its own container.
# Needs the app sources from day 6.
#
# Pulls three base images the first time (node:26-slim, node:26-alpine, python:alpine).
#
# Leaves running:
#   day10-app   port 8110   the multi-stage TypeScript image, with a HEALTHCHECK
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ../day-06/build-steps.sh
need_docker

work=$PWD/.work # scratch space on the server, recreated on every run

# Pull an image only if it is not there yet; retry, because Docker Hub's CDN sometimes drops a request.
pull_once() {
  docker image inspect "$1" >/dev/null 2>&1 && return 0
  for attempt in 1 2 3; do
    docker pull -q "$1" >/dev/null && return 0
    sleep 3
  done
  echo "could not pull $1" >&2
  return 1
}
size() { docker image inspect "$1" --format '{{.Size}}' | numfmt --to=si --suffix=B; }
health() { docker container inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' day10-app; }
# wait_for_health STATUS SECONDS: print the status each second until it is reached
wait_for_health() {
  local want=$1 seconds=$2 s
  for _ in $(seq 1 "$seconds"); do
    s=$(health)
    printf '  health: %s\n' "$s"
    [ "$s" = "$want" ] && return 0
    sleep 1
  done
  return 1
}

docker rm -f day10-app day10-extract >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$work"

step "1. Alpine Linux: a very small base (slides 217-219)"
for image in node:26 node:26-slim node:26-alpine python:slim python:alpine; do pull_once "$image"; done
echo "The same Node.js 26, on three different Linux bases:"
for image in node:26 node:26-slim node:26-alpine; do
  printf '  %-16s %8s   %s\n' "$image" "$(size "$image")" "$(docker run --rm "$image" sh -c '. /etc/os-release; echo "$PRETTY_NAME"')"
done

step "2. The same app on each base (slide 219)"
echo "One Dockerfile with the base image as a build argument (variants/Dockerfile):"
build --build-arg BASE=node:26 -t day10-app:debian -f variants/Dockerfile ../day-06/app
build --build-arg BASE=node:26-slim -t day10-app:slim -f variants/Dockerfile ../day-06/app
build --build-arg BASE=node:26-alpine -t day10-app:alpine -f variants/Dockerfile ../day-06/app
echo
echo "Resulting image sizes:"
for tag in debian slim alpine; do printf '  day10-app:%-8s %8s\n' "$tag" "$(size day10-app:$tag)"; done

step "3. musl versus glibc: the C library underneath (slide 221)"
echo "Debian-based images use glibc:"
printf '  node:26-slim:   %s\n' "$(docker run --rm node:26-slim ldd --version 2>&1 | head -1)"
echo "Alpine uses musl:"
printf '  node:26-alpine: %s\n' "$(docker run --rm node:26-alpine ldd 2>&1 | head -1)"

step "4. Problem: programs built for glibc do not run on Alpine (slides 222-224)"
echo "Take an ordinary program (ls) from a glibc image and try it on both:"
run docker create --name day10-extract python:slim
run docker cp day10-extract:/bin/ls "$work/ls-glibc"
docker rm day10-extract >/dev/null
echo "On the Debian-based image it runs:"
printf '\033[2m$ docker run --rm -v WORK:/x:ro node:26-slim /x/ls-glibc /x\033[0m\n'
docker run --rm -v "$work:/x:ro" node:26-slim /x/ls-glibc /x | sed 's/^/  /'
echo "On Alpine it cannot even start. 'not found' refers to the glibc loader the program asks for, not to the file:"
printf '\033[2m$ docker run --rm -v WORK:/x:ro node:26-alpine /x/ls-glibc /x\033[0m\n'
docker run --rm -v "$work:/x:ro" node:26-alpine /x/ls-glibc /x 2>&1 | sed 's/^/  /' || true
echo
echo "The same problem affects pip. Pre-built Python packages ('wheels') exist per C library;"
echo "pip lists which kinds it can use. A package that ships only glibc wheels has to be"
echo "compiled from source on Alpine, which needs a compiler and takes much longer (slide 224)."
printf '  python:slim   (glibc) accepts: %s\n' "$(docker run --rm python:slim pip debug --verbose 2>/dev/null | grep -oE '(many|musl)linux_[0-9]+_[0-9]+' | sort -u | head -2 | paste -sd' ')..."
printf '  python:alpine (musl)  accepts: %s\n' "$(docker run --rm python:alpine pip debug --verbose 2>/dev/null | grep -oE '(many|musl)linux_[0-9]+_[0-9]+' | sort -u | head -2 | paste -sd' ')"

step "5. A compile step makes images large (slide 226)"
echo "ts-app is the TypeScript version of the app. It must be compiled with 'tsc',"
echo "a development dependency, before it can run. Single stage (ts-app/Dockerfile.single):"
build -t day10-ts:single -f ts-app/Dockerfile.single ts-app
echo
echo "The compiler and the sources stay in the final image, although the running app needs neither:"
printf '  node_modules/typescript present: '
docker run --rm day10-ts:single sh -c 'test -d node_modules/typescript && echo yes || echo no'
printf '  src/server.ts present:           '
docker run --rm day10-ts:single sh -c 'test -f src/server.ts && echo yes || echo no'
printf '  size: %s\n' "$(size day10-ts:single)"

step "6. Multi-stage build: compile in one image, run in another (slides 227-228)"
echo "ts-app/Dockerfile has two FROM lines. Stage 'builder' compiles; stage 'runtime' is Alpine"
echo "and receives only dist/, with COPY --from=builder:"
grep -E '^(FROM|COPY --from)' ts-app/Dockerfile | sed 's/^/  /'
echo
build -t day10-ts:multistage ts-app
echo
printf '  node_modules/typescript present: '
docker run --rm day10-ts:multistage sh -c 'test -d node_modules/typescript && echo yes || echo no'
printf '  src/server.ts present:           '
docker run --rm day10-ts:multistage sh -c 'test -f src/server.ts && echo yes || echo no'
printf '  dist/server.js present:          '
docker run --rm day10-ts:multistage sh -c 'test -f dist/server.js && echo yes || echo no'
echo
printf '  single stage: %8s\n  multi-stage:  %8s\n' "$(size day10-ts:single)" "$(size day10-ts:multistage)"

step "7. HEALTHCHECK (slide 230)"
echo "The Dockerfile's check, as Docker stored it in the image:"
docker image inspect day10-ts:multistage --format '  test:     {{json .Config.Healthcheck.Test}}{{"\n"}}  interval: {{.Config.Healthcheck.Interval}}   timeout: {{.Config.Healthcheck.Timeout}}   retries: {{.Config.Healthcheck.Retries}}'
run docker run -d --name day10-app -p 8110:3000 --restart unless-stopped day10-ts:multistage
echo
echo "A new container starts as 'starting' and becomes 'healthy' after the first successful check:"
wait_for_health healthy 20
echo
echo "Now break it on purpose. The app reports an error on /health while the file /tmp/unhealthy exists:"
run docker exec day10-app touch /tmp/unhealthy
echo "/health now answers: HTTP $(curl -s -o /dev/null -m 3 -w '%{http_code}' http://localhost:8110/health)"
wait_for_health unhealthy 30
echo "docker ps shows it:"
docker ps --filter name=day10-app --format '  {{.Names}}  {{.Status}}'
echo "Docker only records this. Plain Docker does not restart an unhealthy container;"
echo "orchestrators such as Docker Swarm and Kubernetes act on the status (later days)."
echo
echo "Repair it:"
run docker exec day10-app rm /tmp/unhealthy
wait_for_health healthy 20

step "8. Summary: image sizes"
printf '  %-28s %8s\n' "day10-app:debian  (node:26)" "$(size day10-app:debian)"
printf '  %-28s %8s\n' "day10-app:slim" "$(size day10-app:slim)"
printf '  %-28s %8s\n' "day10-app:alpine" "$(size day10-app:alpine)"
printf '  %-28s %8s\n' "day10-ts:single" "$(size day10-ts:single)"
printf '  %-28s %8s\n' "day10-ts:multistage" "$(size day10-ts:multistage)"

step "Done"
echo "day10-app  http://localhost:8110  (health: $(health))"
echo "Next: setup/run.sh day-10/verify.sh"

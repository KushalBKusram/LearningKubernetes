#!/usr/bin/env bash
# Day 07 lab: your own registry and CPU architectures (slides 158-168).
# Runs on the server. Safe to run more than once. The registry's data lives in a
# named volume, so images pushed earlier survive a re-run.
#
# Needs the image day06-app from day 6 (run day-06/lab.sh first).
#
# Leaves running:
#   day07-registry   127.0.0.1:5000   registry:2 protected with a password (HTTP basic auth)
#
# The registry user is "courselab". Its password is generated once and kept in
# ~/.course/registry-password (readable only by you). Days 9 and later read it from there.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

REG=localhost:5000
USER_NAME=courselab
CRED_DIR=$HOME/.course
PW_FILE=$CRED_DIR/registry-password
HTPASSWD=$CRED_DIR/registry-htpasswd
work=$PWD/.work # scratch space on the server, recreated on every run

docker image inspect day06-app >/dev/null 2>&1 || {
  echo "The image day06-app does not exist. Run: setup/run.sh day-06/lab.sh" >&2
  exit 1
}

docker rm -f day07-registry day07-registry-open >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$work" "$CRED_DIR"
chmod 700 "$CRED_DIR"

status() { curl -s -o /dev/null -m 3 -w '%{http_code}' "$@" || true; }
wait_for_registry() { for _ in $(seq 1 20); do [ "$(status "http://$REG/v2/")" != "000" ] && return 0; sleep 0.5; done; }

step "1. A registry is just a container (slide 166)"
docker image inspect registry:2 >/dev/null 2>&1 || docker pull -q registry:2 >/dev/null
docker volume create day07-registry-data >/dev/null
# 127.0.0.1: the registry is only reachable from this machine. Basic auth sends the
# password unencrypted over plain HTTP, so it must not be exposed to the network.
run docker run -d --name day07-registry-open -p 127.0.0.1:5000:5000 -v day07-registry-data:/var/lib/registry registry:2
wait_for_registry
echo "Asking it what it holds: $(curl -s -m 3 http://$REG/v2/_catalog)"

step "2. Tag, push, pull (slide 166)"
run docker image tag day06-app "$REG/day06-app:1.0.0"
run docker image tag day06-app "$REG/day06-app:latest"
run docker push "$REG/day06-app:1.0.0"
echo "The registry now lists: $(curl -s -m 3 http://$REG/v2/_catalog)"
echo "Tags of day06-app:      $(curl -s -m 3 http://$REG/v2/day06-app/tags/list)"
echo
echo "Delete the local copies and pull the image back from the registry:"
run docker image rm "$REG/day06-app:1.0.0" "$REG/day06-app:latest"
run docker pull "$REG/day06-app:1.0.0"
echo "Running the pulled image: $(docker run --rm "$REG/day06-app:1.0.0" node --version)"

step "3. Anyone who can reach it can push and pull. Add a password (slide 168)"
if [ ! -s "$PW_FILE" ]; then
  head -c 24 /dev/urandom | base64 | tr -d '/+=\n' | head -c 24 >"$PW_FILE"
  chmod 600 "$PW_FILE"
  echo "Generated a password for $USER_NAME in $PW_FILE (not shown here)."
else
  echo "Using the password already in $PW_FILE."
fi
echo "The .htpasswd file is made with htpasswd from the httpd image. The password is passed on stdin:"
printf '\033[2m$ docker run -i --rm httpd htpasswd -Bin %s < password-file\033[0m\n' "$USER_NAME"
docker run -i --rm httpd htpasswd -Bin "$USER_NAME" <"$PW_FILE" >"$HTPASSWD"
chmod 644 "$HTPASSWD"
echo "Its content (user, then a bcrypt hash of the password):"
sed -E 's/(\$2y\$[0-9]+\$.{8}).*/\1.../' "$HTPASSWD" | grep -v '^$' | sed 's/^/  /'

step "4. Restart the registry with authentication (slide 168)"
docker rm -f day07-registry-open >/dev/null
run docker run -d --name day07-registry --restart unless-stopped \
  -p 127.0.0.1:5000:5000 \
  -v day07-registry-data:/var/lib/registry \
  -v "$HTPASSWD:/auth/htpasswd:ro" \
  -e REGISTRY_AUTH=htpasswd \
  -e 'REGISTRY_AUTH_HTPASSWD_REALM=Course registry' \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  registry:2
wait_for_registry
echo "Without credentials:  HTTP $(status http://$REG/v2/_catalog)  (401 = authentication required)"
echo "Wrong password:       HTTP $(status -u "$USER_NAME:wrong-password" http://$REG/v2/_catalog)"
echo "With the password:    HTTP $(status -u "$USER_NAME:$(cat "$PW_FILE")" http://$REG/v2/_catalog)"
echo "The image pushed before the restart is still there: $(curl -s -m 3 -u "$USER_NAME:$(cat "$PW_FILE")" http://$REG/v2/_catalog)"
echo
echo "docker push without logging in is refused:"
if out=$(DOCKER_CONFIG="$work/empty-docker-config" docker push "$REG/day06-app:1.0.0" 2>&1); then
  echo "  UNEXPECTED: it worked"
else
  echo "$out" | tail -1 | sed 's/^/  /'
fi
echo
echo "Log in (the password goes in on stdin, so it is not in the shell history):"
printf '\033[2m$ docker login %s -u %s --password-stdin < password-file\033[0m\n' "$REG" "$USER_NAME"
docker login "$REG" -u "$USER_NAME" --password-stdin <"$PW_FILE" 2>&1 | grep -v '^$' | sed 's/^/  /'
run docker push "$REG/day06-app:1.0.0"

step "5. CPU architectures (slides 161-164)"
echo "This machine:                $(uname -m)  (Docker calls it linux/$(docker info --format '{{.Architecture}}' | sed 's/x86_64/amd64/;s/aarch64/arm64/'))"
echo "The image day06-app was built for: $(docker image inspect day06-app --format '{{.Os}}/{{.Architecture}}')"
echo "A Mac with an Apple chip would have built the same Dockerfile as linux/arm64, which would not run here."
echo
echo "The Docker Hub image hello-world:linux is built for many architectures (a manifest list):"
docker buildx imagetools inspect hello-world:linux | grep 'Platform:' | grep -v unknown | sed 's/^ */  /'
echo
echo "Pull the arm64 variant and try to run it on this x86_64 machine (--platform, slide 164):"
run docker pull -q --platform linux/arm64 hello-world:linux
docker tag hello-world:linux day07-hello-arm64 2>/dev/null || true
echo "Architecture of the pulled image: $(docker image inspect hello-world:linux --platform linux/arm64 --format '{{.Os}}/{{.Architecture}}')"
printf '\033[2m$ docker run --rm --platform linux/arm64 hello-world:linux\033[0m\n'
if out=$(docker run --rm --platform linux/arm64 hello-world:linux 2>&1); then
  echo "  It ran: this machine has CPU emulation (QEMU) installed, at a significant speed cost."
else
  echo "$out" | tail -2 | sed 's/^/  /'
  echo "  No emulation is installed, so the arm64 build cannot run here."
fi
echo "The amd64 variant runs natively:"
printf '\033[2m$ docker run --rm --platform linux/amd64 hello-world\033[0m\n'
docker run --rm --platform linux/amd64 hello-world | grep 'Hello from Docker' | sed 's/^/  /'

step "6. One image name, several architectures: a multi-platform build (slide 164)"
echo "An image has to be built once per architecture. A tiny image with no RUN steps needs no"
echo "emulation to build, so it shows the idea for both architectures on this machine."
mkdir -p "$work/multiarch"
cat >"$work/multiarch/Dockerfile" <<'EOF'
FROM scratch
ARG TARGETARCH
LABEL arch="$TARGETARCH"
COPY hello.txt /hello.txt
EOF
echo "hello from a multi-architecture image" >"$work/multiarch/hello.txt"
printf '\033[2m$ docker buildx build --platform linux/amd64,linux/arm64 -t %s/day07-multiarch:1 --push .\033[0m\n' "$REG"
if ! out=$(docker buildx build --provenance=false --platform linux/amd64,linux/arm64 \
  -t "$REG/day07-multiarch:1" --push "$work/multiarch" 2>&1); then
  echo "$out"
  exit 1
fi
echo "  built and pushed for linux/amd64 and linux/arm64"
echo
echo "The registry holds one name that points to one image per architecture:"
docker buildx imagetools inspect "$REG/day07-multiarch:1" | grep -E 'Name:|MediaType:|Platform:' | sed 's/^ */  /'
echo
echo "docker pull picks the variant that matches the machine:"
run docker pull -q "$REG/day07-multiarch:1"
echo "Variant pulled here: $(docker image inspect "$REG/day07-multiarch:1" --format '{{.Os}}/{{.Architecture}}')"

step "Done"
echo "day07-registry  http://$REG  (user $USER_NAME, password in $PW_FILE)"
echo "Next: setup/run.sh day-07/verify.sh"

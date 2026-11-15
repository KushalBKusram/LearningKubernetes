#!/usr/bin/env bash
# Day 07 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

REG=localhost:5000
USER_NAME=courselab
PW_FILE=$HOME/.course/registry-password
tmpcfg=$(mktemp -d)
trap 'rm -rf "$tmpcfg"' EXIT

code() { curl -s -o /dev/null -m 3 -w '%{http_code}' "$@"; }
authed() { curl -s -m 5 -u "$USER_NAME:$(cat "$PW_FILE")" "$@"; }

running() { [ "$(docker container inspect -f '{{.State.Running}}' day07-registry)" = "true" ]; }
restart_policy() { [ "$(docker container inspect -f '{{.HostConfig.RestartPolicy.Name}}' day07-registry)" = "unless-stopped" ]; }
local_only() { docker port day07-registry 5000/tcp | grep -qx '127.0.0.1:5000'; }
has_volume() { docker volume inspect day07-registry-data; }
password_file_private() { [ "$(stat -c %a "$PW_FILE")" = "600" ]; }
anonymous_refused() { [ "$(code http://$REG/v2/_catalog)" = "401" ]; }
wrong_password_refused() { [ "$(code -u "$USER_NAME:wrong-password" http://$REG/v2/_catalog)" = "401" ]; }
password_accepted() { [ "$(code -u "$USER_NAME:$(cat "$PW_FILE")" http://$REG/v2/_catalog)" = "200" ]; }
catalog_has() { authed "http://$REG/v2/_catalog" | jq -e --arg r "$1" '.repositories | index($r)'; }
tag_listed() { authed "http://$REG/v2/day06-app/tags/list" | jq -e '.tags | index("1.0.0")'; }
login_rejects_wrong_pw() { ! echo wrong-password | DOCKER_CONFIG="$tmpcfg" docker login "$REG" -u "$USER_NAME" --password-stdin; }
login_accepts_pw() { DOCKER_CONFIG="$tmpcfg" docker login "$REG" -u "$USER_NAME" --password-stdin <"$PW_FILE"; }
push_needs_login() { ! DOCKER_CONFIG="$tmpcfg/none" docker push "$REG/day06-app:1.0.0"; }
# Compare the layers, not the image ID: rebuilding an image (day 6's checks do) gives it a
# new ID even when every layer is identical, but the layers are what the registry stores.
roundtrip() {
  local want got
  want=$(docker image inspect day06-app --format '{{json .RootFS.Layers}}')
  docker image rm "$REG/day06-app:1.0.0" >/dev/null 2>&1
  docker pull -q "$REG/day06-app:1.0.0" >/dev/null || return 1
  got=$(docker image inspect "$REG/day06-app:1.0.0" --format '{{json .RootFS.Layers}}')
  [ "$want" = "$got" ]
}
pulled_image_runs() { docker run --rm "$REG/day06-app:1.0.0" node --version | grep -qE '^v[0-9]+'; }
host_is_amd64() { [ "$(docker info --format '{{.Architecture}}')" = "x86_64" ]; }
arm_variant_is_arm() { [ "$(docker image inspect hello-world:linux --platform linux/arm64 --format '{{.Architecture}}')" = "arm64" ]; }
# Output is captured before grep: "grep -q" can exit early and, with pipefail, the SIGPIPE would fail a correct run.
amd64_runs() { local out; out=$(docker run --rm --platform linux/amd64 hello-world); grep -q 'Hello from Docker' <<<"$out"; }
two_platforms() {
  [ "$(docker buildx imagetools inspect "$REG/day07-multiarch:1" --raw | jq '[.manifests[] | select(.platform.architecture != "unknown")] | length')" = "2" ]
}
both_archs() {
  docker buildx imagetools inspect "$REG/day07-multiarch:1" --raw |
    jq -e '[.manifests[].platform.architecture] | (index("amd64") != null) and (index("arm64") != null)'
}
open_registry_gone() { [ -z "$(docker container ls -aq --filter name=day07-registry-open)" ]; }

step "Day 07 verification"
echo "the registry container"
check "day07-registry is running" running
check "restart policy is unless-stopped" restart_policy
check "it listens on 127.0.0.1 only, not on the network" local_only
check "its data is in the named volume day07-registry-data" has_volume
check "the open (password-less) registry container was removed" open_registry_gone
echo "authentication"
check "the password file is readable only by you (mode 600)" password_file_private
check "no credentials: HTTP 401" anonymous_refused
check "wrong password: HTTP 401" wrong_password_refused
check "correct password: HTTP 200" password_accepted
check "docker login refuses a wrong password" login_rejects_wrong_pw
check "docker login accepts the right password" login_accepts_pw
check "docker push without logging in is refused" push_needs_login
echo "push and pull"
check "the catalog lists day06-app" catalog_has day06-app
check "day06-app has the tag 1.0.0" tag_listed
check "delete locally, pull back: the same layers" roundtrip
check "the image pulled from the registry runs" pulled_image_runs
echo "CPU architectures"
check "this machine is x86_64 (linux/amd64)" host_is_amd64
check "the pulled hello-world:linux variant is arm64" arm_variant_is_arm
check "the amd64 variant runs here with --platform linux/amd64" amd64_runs
check "the multi-platform image in the registry has two platforms" two_platforms
check "those platforms are amd64 and arm64" both_archs
summary

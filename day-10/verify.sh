#!/usr/bin/env bash
# Day 10 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

bytes() { docker image inspect "$1" --format '{{.Size}}'; }
has_image() { docker image inspect "$1"; }
smaller() { [ "$(bytes "$1")" -lt "$(bytes "$2")" ]; }
at_least_3x_smaller() { [ $(($(bytes "$2") / $(bytes "$1"))) -ge 3 ]; }
os_of() { docker run --rm "$1" sh -c '. /etc/os-release; echo "$ID"'; }
is_debian() { [ "$(os_of "$1")" = "debian" ]; }
is_alpine() { [ "$(os_of "$1")" = "alpine" ]; }
# Capture the output first: "grep -q" exits at the first match, and with pipefail the
# resulting SIGPIPE to docker would make a correct result look like a failure.
glibc_in_slim() { local out; out=$(docker run --rm node:26-slim ldd --version 2>&1); grep -qi glibc <<<"$out"; }
musl_in_alpine() { local out; out=$(docker run --rm node:26-alpine ldd 2>&1); grep -qi musl <<<"$out"; }
app_runs_on() { local out; out=$(docker run --rm "$1" node -e 'require("express"); console.log("ok")'); [ "$out" = ok ]; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; docker rm -f day10-extract >/dev/null 2>&1' EXIT
docker rm -f day10-extract >/dev/null 2>&1
docker create --name day10-extract python:slim >/dev/null 2>&1 && docker cp day10-extract:/bin/ls "$tmp/ls-glibc" >/dev/null 2>&1
docker rm -f day10-extract >/dev/null 2>&1
glibc_binary_runs_on_slim() { local out; out=$(docker run --rm -v "$tmp:/x:ro" node:26-slim /x/ls-glibc /x); grep -q ls-glibc <<<"$out"; }
glibc_binary_fails_on_alpine() { ! docker run --rm -v "$tmp:/x:ro" node:26-alpine /x/ls-glibc /x; }
pip_tags() { docker run --rm "$1" pip debug --verbose 2>/dev/null | grep -oE '(many|musl)linux' | sort -u | paste -sd,; }
slim_wheels_glibc() { [ "$(pip_tags python:slim)" = "manylinux" ]; }
alpine_wheels_musl() { [ "$(pip_tags python:alpine)" = "musllinux" ]; }

has_path() { docker run --rm "$1" sh -c "test -e $2"; }
single_has_compiler() { has_path day10-ts:single /app/node_modules/typescript; }
single_has_sources() { has_path day10-ts:single /app/src/server.ts; }
multi_lacks_compiler() { ! has_path day10-ts:multistage /app/node_modules/typescript; }
multi_lacks_sources() { ! has_path day10-ts:multistage /app/src/server.ts; }
multi_has_dist() { has_path day10-ts:multistage /app/dist/server.js; }
multi_has_runtime_dep() { has_path day10-ts:multistage /app/node_modules/express; }
two_stages() { [ "$(grep -c '^FROM ' ts-app/Dockerfile)" = "2" ]; }
copy_from_builder() { grep -q '^COPY --from=builder' ts-app/Dockerfile; }
multi_not_root() { [ "$(docker run --rm day10-ts:multistage id -u)" != "0" ]; }

hc_defined() { [ "$(docker image inspect day10-ts:multistage --format '{{len .Config.Healthcheck.Test}}')" -gt 0 ]; }
no_hc_in_single() { [ "$(docker image inspect day10-ts:single --format '{{if .Config.Healthcheck}}yes{{else}}no{{end}}')" = "no" ]; }
status() { docker container inspect -f '{{.State.Health.Status}}' day10-app; }
await() { local want=$1 i; for i in $(seq 1 25); do [ "$(status)" = "$want" ] && return 0; sleep 1; done; return 1; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' day10-app)" = "true" ]; }
healthy() { await healthy; }
serves() { curl -s -m 3 http://localhost:8110/api/info | jq -e '.greeting == "Hello from the TypeScript app"'; }
flips_to_unhealthy() {
  docker exec day10-app touch /tmp/unhealthy && await unhealthy
}
recovers() {
  docker exec day10-app rm -f /tmp/unhealthy && await healthy
}
temp_gone() { [ -z "$(docker container ls -aq --filter name=day10-extract)" ]; }

step "Day 10 verification"
echo "base images and sizes"
check "image day10-app:debian exists" has_image day10-app:debian
check "image day10-app:slim exists" has_image day10-app:slim
check "image day10-app:alpine exists" has_image day10-app:alpine
check "slim is smaller than the default Debian-based image" smaller day10-app:slim day10-app:debian
check "alpine is smaller than slim" smaller day10-app:alpine day10-app:slim
check "node:26 and node:26-slim are Debian" is_debian node:26-slim
check "node:26-alpine is Alpine" is_alpine node:26-alpine
check "the app starts on the Alpine variant" app_runs_on day10-app:alpine
echo "musl versus glibc"
check "Debian-based images use glibc" glibc_in_slim
check "Alpine uses musl" musl_in_alpine
check "a glibc program runs on Debian slim" glibc_binary_runs_on_slim
check "the same program cannot run on Alpine" glibc_binary_fails_on_alpine
check "pip on Debian slim accepts manylinux (glibc) wheels only" slim_wheels_glibc
check "pip on Alpine accepts musllinux wheels only" alpine_wheels_musl
echo "multi-stage builds"
check "the Dockerfile has two stages" two_stages
check "it copies the result from the builder stage" copy_from_builder
check "single stage: the compiler stays in the image" single_has_compiler
check "single stage: the sources stay in the image" single_has_sources
check "multi-stage: no compiler in the image" multi_lacks_compiler
check "multi-stage: no sources in the image" multi_lacks_sources
check "multi-stage: the compiled dist/server.js is there" multi_has_dist
check "multi-stage: production dependencies are there" multi_has_runtime_dep
check "multi-stage image is at least 3 times smaller than single stage" at_least_3x_smaller day10-ts:multistage day10-ts:single
check "multi-stage image does not run as root" multi_not_root
echo "HEALTHCHECK"
check "the multi-stage image defines a HEALTHCHECK" hc_defined
check "the single-stage image defines none" no_hc_in_single
check "day10-app is running" running
check "its status is healthy" healthy
check "port 8110 serves the TypeScript app" serves
check "a failing /health turns the status to unhealthy" flips_to_unhealthy
check "repairing it turns the status back to healthy" recovers
check "temporary container was removed" temp_gone
summary

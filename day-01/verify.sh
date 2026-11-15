#!/usr/bin/env bash
# Day 01 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

has_image() { docker image inspect "$1"; }
different_versions() {
  [ "$(docker run --rm python:slim python --version)" != "$(docker run --rm python:3.12-slim python --version)" ]
}
image_unchanged() { ! docker run --rm ubuntu cat /note.txt; }
no_leftovers() { [ -z "$(docker container ls -aq --filter name=day01-)" ]; }

step "Day 01 verification"
check "hello-world runs" docker run --rm hello-world
check "image present: ubuntu" has_image ubuntu
check "image present: fedora" has_image fedora
check "image present: python (latest)" has_image python:latest
check "image present: python:slim" has_image python:slim
check "image present: node" has_image node
check "python:slim and python:3.12-slim are different Python versions" different_versions
check "a fresh ubuntu container has no /note.txt (image is immutable)" image_unchanged
check "no day01 containers left behind" no_leftovers
summary

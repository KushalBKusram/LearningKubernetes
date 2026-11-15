#!/usr/bin/env bash
# Settings for the scripts that run on your own computer (the "Mac" in the docs).
# Source this file; do not run it.
#
# Values, highest priority first:
#   1. environment variables you set when running a script:  COURSE_HOST=my-server setup/run.sh ...
#   2. setup/local.env, a file of your own that is not committed (copy local.env.example)
#   3. the defaults below
#
#   COURSE_HOST         the SSH name of the server that runs everything (a Host in ~/.ssh/config)
#   COURSE_REMOTE_DIR   where the project is copied to on the server, relative to its home folder

_course_setup_dir=${COURSE_SETUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}
if [ -f "$_course_setup_dir/local.env" ]; then
  # shellcheck disable=SC1091
  . "$_course_setup_dir/local.env"
fi

COURSE_HOST=${COURSE_HOST:-course-server}
COURSE_REMOTE_DIR=${COURSE_REMOTE_DIR:-Projects/Kubernetes}

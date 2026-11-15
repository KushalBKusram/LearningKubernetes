#!/usr/bin/env bash
# Source this in your shell (bash or zsh) so that the commands in the day READMEs work as written:
#
#   source setup/env.sh
#
# It sets:
#   COURSE_HOST  the SSH name of the server       (used as:  ssh "$COURSE_HOST" ...)
#   SERVER       the address that name resolves to in ~/.ssh/config, or COURSE_DOMAIN if you set it
#                (used as:  curl http://$SERVER:8888)

if [ -n "${BASH_VERSION:-}" ]; then
  _env_file=${BASH_SOURCE[0]}
else
  # zsh: the path of the file being sourced
  _env_file=${(%):-%x}
fi
COURSE_SETUP_DIR=$(cd "$(dirname "$_env_file")" && pwd)
export COURSE_SETUP_DIR
# shellcheck disable=SC1091
. "$COURSE_SETUP_DIR/config.sh"
export COURSE_HOST COURSE_REMOTE_DIR
SERVER=${COURSE_DOMAIN:-$(ssh -G "$COURSE_HOST" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')}
export SERVER
unset _env_file
echo "COURSE_HOST=$COURSE_HOST  SERVER=$SERVER"

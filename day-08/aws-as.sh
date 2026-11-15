#!/usr/bin/env bash
# Run one AWS CLI command against the moto server as one of the lab's users.
# Runs on the server. From the Mac:
#
#   setup/run.sh day-08/aws-as.sh cli-admin ec2 describe-instances --output table
#   setup/run.sh day-08/aws-as.sh monitor-script iam list-users
#
# Users with a stored access key: cli-admin, monitor-script.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./common.sh
need_docker

if [ $# -lt 2 ]; then
  echo "usage: aws-as.sh <cli-admin|monitor-script> <aws arguments...>" >&2
  exit 2
fi
use_user "$1"
shift
aws "$@"

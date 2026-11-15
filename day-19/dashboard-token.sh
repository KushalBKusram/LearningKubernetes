#!/usr/bin/env bash
# Prints a login token for the dashboard, valid for one hour (slide 384).
# Run on the server, or from the Mac:  setup/run.sh day-19/dashboard-token.sh
#
# The token belongs to the user "dashboard-admin", who may do anything in the
# cluster. Paste it into the login page at http://<server>:30089
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./k8s-lib.sh
need_cluster
K8S_NAMESPACE=day19

kubectl create token dashboard-admin --duration=1h

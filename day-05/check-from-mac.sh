#!/usr/bin/env bash
# Day 05, seen from the Mac. Run ON THE MAC:
#
#   day-05/check-from-mac.sh
#
# Fetches Caddy's root certificate from the server into day-05/caddy-root.crt
# and uses it for this one check. Nothing is added to the Mac's keychain.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../setup/config.sh"
HOST=$COURSE_HOST
cd "$here"
fqdn=$(ssh -G "$HOST" 2>/dev/null | awk '$1 == "hostname" { print $2 }')
ca=caddy-root.crt
fail=0

scp -q "$HOST:$COURSE_REMOTE_DIR/day-05/.work/caddy-root.crt" "$ca" || {
  echo "Could not fetch the root certificate. Run this first: setup/run.sh day-05/lab.sh" >&2
  exit 1
}

echo "== The name resolves to the server"
echo "  $fqdn -> $(dig +short "$fqdn" A 2>/dev/null | head -1)"

echo "== http:// is redirected to https://"
head=$(curl -s -m 8 -I "http://$fqdn")
echo "$head" | grep -iE '^(HTTP|location)' | sed 's/^/  /'
echo "$head" | grep -qi "^location: https://$fqdn" || { echo "  FAIL: no redirect to https"; fail=1; }

echo "== https:// without trusting Caddy's authority (what a browser does by default)"
if curl -s -S -m 8 -o /dev/null "https://$fqdn" 2>/tmp/day05-curl-err; then
  echo "  FAIL: the certificate was accepted without the root certificate"
  fail=1
else
  head -1 /tmp/day05-curl-err | sed 's/^/  refused: /'
fi
rm -f /tmp/day05-curl-err

echo "== https:// trusting Caddy's root certificate"
page=$(curl -s -m 8 --cacert "$ca" "https://$fqdn")
if echo "$page" | grep -qF 'day-05 site'; then
  echo "$page" | grep -o '<h1>.*</h1>' | sed 's/^/  /'
else
  echo "  FAIL: the page was not served over a verified connection"
  fail=1
fi

echo
[ "$fail" -eq 0 ] && echo "All checks from the Mac passed." || echo "Some checks from the Mac failed."
exit "$fail"

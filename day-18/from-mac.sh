#!/usr/bin/env bash
# Day 18, seen from "our own computer" (slides 341-342, 351). Run ON THE MAC:
#
#   day-18/from-mac.sh
#
# 1. Loads both HTTPS sites, checking the certificate against the load
#    balancer's certificate authority.
# 2. Turns the SFTP server on, uploads a picture from this Mac straight onto the
#    shared volume, checks that the website serves it, and turns SFTP off again.
#
# Nothing is left on the Mac: it works in a temporary folder with a throwaway key.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/../setup/config.sh"
HOST=$COURSE_HOST
REMOTE_DIR=$COURSE_REMOTE_DIR
fqdn=$(ssh -G "$HOST" 2>/dev/null | awk '$1 == "hostname" { print $2 }')

tmp=$(mktemp -d)
cleanup() {
  ssh "$HOST" "docker exec day18-sftp sed -i '/day18-from-mac/d' /etc/ssh/authorized_keys/upload; docker stop day18-sftp" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

echo "== 1. HTTPS from the Mac (slide 351)"
ssh "$HOST" "cat '$REMOTE_DIR/day-18/.work/root.crt'" >"$tmp/root.crt"
echo "Fetched the load balancer's CA certificate (a public certificate, no secret)."
for port in 8543 8544; do
  url="https://$fqdn:$port/"
  title=$(curl -s -m 15 -L --cacert "$tmp/root.crt" "$url" | grep -o '<title>[^<]*</title>' | head -1)
  echo "  $url -> $title"
done
echo "  http://$fqdn:8580/ -> $(curl -s -m 15 -o /dev/null -w '%{http_code} %{redirect_url}' "http://$fqdn:8580/")"

echo
echo "== 2. SFTP from the Mac onto the shared volume (slides 341-342)"
ssh "$HOST" 'docker start day18-sftp' >/dev/null
echo "SFTP server turned on."
ssh-keygen -q -t ed25519 -N '' -C day18-from-mac -f "$tmp/key"
ssh "$HOST" "docker exec -i day18-sftp sh -c 'cat >> /etc/ssh/authorized_keys/upload'" <"$tmp/key.pub"
# A 1x1 pixel PNG.
echo 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' | base64 --decode >"$tmp/from-mac.png"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  nc -z -w 2 "$fqdn" 8522 >/dev/null 2>&1 && break
  sleep 1
done
echo "\$ sftp -P 8522 upload@$fqdn"
sftp -q -P 8522 -i "$tmp/key" -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$tmp/known_hosts" \
  -b - "upload@$fqdn" <<EOF
put $tmp/from-mac.png uploads/from-mac.png
ls -l uploads
EOF
echo
echo "The website serves the file that came in over SFTP:"
curl -s -m 15 -o /dev/null --cacert "$tmp/root.crt" \
  -w "  https://$fqdn:8543/uploads/from-mac.png -> %{http_code} %{content_type}\n" \
  "https://$fqdn:8543/uploads/from-mac.png"
echo "SFTP server turned off again."

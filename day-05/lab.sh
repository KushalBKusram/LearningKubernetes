#!/usr/bin/env bash
# Day 05 lab: DNS, a domain for the server, and HTTPS with Caddy (slides 115-132).
# Runs on the server. Safe to run more than once: it recreates its own containers.
#
# Leaves running:
#   day05-dns    127.0.0.1:5300   CoreDNS, authoritative for the practice zone course.test
#   day05-caddy  ports 80, 443    Caddy serving the site over HTTPS
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

work=$PWD/.work
# The server's domain name. On the slides this is a domain bought in Route 53;
# here it is the name Tailscale already gives the server.
domain=${COURSE_DOMAIN:-$(tailscale status --self --peers=false --json | jq -r '.Self.DNSName' | sed 's/\.$//')}
ip4=$(tailscale ip -4)
ip6=$(tailscale ip -6)

# One DNS question to one specific server, without letting that server ask others for us.
ask() { dig +norecurse +noall +answer +authority +time=3 +tries=2 "$@"; }
# Ask the practice name server in the day05-dns container.
zone() { dig +short +time=3 +tries=2 @127.0.0.1 -p 5300 "$@"; }
# curl against this machine, but under the real domain name.
local_curl() { curl -s -m 5 --resolve "$domain:80:127.0.0.1" --resolve "$domain:443:127.0.0.1" "$@"; }

docker rm -f -v day05-dns day05-caddy >/dev/null 2>&1 || true
rm -rf "$work"
mkdir -p "$work/zones"

step "1. DNS turns a name into an IP address (slide 118)"
run dig +short google.com A

step "2. Who answers first: the resolver (slides 119-120)"
echo "This machine sends its DNS questions to:"
resolvectl status | grep 'Current DNS Server' | sed 's/^ */  /'
echo "A resolver answers from its cache when it can. Otherwise it walks down from the root:"

step "3. Root name server: who is responsible for .com? (slide 121)"
echo "\$ dig +norecurse @i.root-servers.net com NS"
ask @i.root-servers.net com NS | sed -n '1,3p'
echo "  ... (13 name servers for .com in total)"

step "4. TLD name server: who is responsible for google.com? (slide 122)"
echo "\$ dig +norecurse @e.gtld-servers.net google.com NS"
ask @e.gtld-servers.net google.com NS

step "5. Authoritative name server: the actual answer (slide 123)"
echo "\$ dig +norecurse @ns1.google.com google.com A"
ask @ns1.google.com google.com A
flags=$(dig +norecurse +time=3 @ns1.google.com google.com A | grep -o 'flags: [a-z ]*')
echo "  $flags   ('aa' = authoritative answer)"

step "6. Record types (slide 126)"
run host -t A google.com
run host -t AAAA google.com
run host -t MX google.com
run host -t NS google.com
run host -t TXT example.com
run host -t CNAME www.github.com

step "7. Our own zone: configuring DNS records (slide 128)"
echo "Route 53 stand-in: a CoreDNS container that is authoritative for the practice domain course.test."
sed -e "s/@SERVER_IP4@/$ip4/g" -e "s/@SERVER_IP6@/$ip6/g" dns/course.test.zone.template >"$work/zones/course.test.zone"
run docker create --name day05-dns -p 127.0.0.1:5300:1053/udp -p 127.0.0.1:5300:1053/tcp \
  --restart unless-stopped coredns/coredns -conf /Corefile
run docker cp dns/Corefile day05-dns:/Corefile
run docker cp "$work/zones" day05-dns:/zones
run docker start day05-dns
for _ in $(seq 1 20); do
  [ -n "$(zone course.test A 2>/dev/null)" ] && break
  sleep 0.5
done
echo
echo "Asking our name server (dig @127.0.0.1 -p 5300 ...):"
printf '  %-22s %-6s %s\n' "course.test" "A" "$(zone course.test A)"
printf '  %-22s %-6s %s\n' "course.test" "AAAA" "$(zone course.test AAAA)"
printf '  %-22s %-6s %s\n' "www.course.test" "CNAME" "$(zone www.course.test CNAME)"
printf '  %-22s %-6s %s\n' "course.test" "MX" "$(zone course.test MX)"
printf '  %-22s %-6s %s\n' "course.test" "TXT" "$(zone course.test TXT)"
printf '  %-22s %-6s %s\n' "course.test" "NS" "$(zone course.test NS)"
echo "The A record is the one that connects a domain to a server: course.test -> $ip4 (this machine)."

step "8. The domain this server really has (slide 128)"
echo "Only this practice server knows course.test. The name that resolves everywhere on the tailnet is:"
echo "  $domain"
run dig +short "$domain" A
echo "Tailscale's DNS holds that A record, the way Route 53 would for a bought domain."

step "9. Caddy: a web server that sets up HTTPS by itself (slides 131-132)"
docker volume create day05-caddy-data >/dev/null # keeps Caddy's certificate authority across re-runs
run docker create --name day05-caddy -p 80:80 -p 443:443 -e "DOMAIN=$domain" \
  -v day05-caddy-data:/data --restart unless-stopped caddy
run docker cp Caddyfile day05-caddy:/etc/caddy/Caddyfile
run docker cp site/. day05-caddy:/srv/
run docker start day05-caddy
echo "Waiting for Caddy to issue the certificate..."
for _ in $(seq 1 40); do
  docker exec day05-caddy test -f /data/caddy/pki/authorities/local/root.crt 2>/dev/null &&
    [ "$(local_curl -k -o /dev/null -w '%{http_code}' "https://$domain")" = "200" ] && break
  sleep 0.5
done

step "10. HTTP is redirected to HTTPS"
echo "\$ curl -I http://$domain"
local_curl -I "http://$domain" | grep -iE '^(HTTP|location)' | sed 's/^/  /' || true

step "11. Who vouches for the certificate?"
echo "Without knowing Caddy's certificate authority, curl refuses the connection, as a browser would warn:"
if out=$(local_curl -S "https://$domain" 2>&1 >/dev/null); then
  echo "  UNEXPECTED: the certificate was accepted"
else
  echo "$out" | head -1 | sed 's/^/  /'
fi
echo
echo "Caddy's root certificate is public information. Copy it out of the container (docker cp, day 4):"
run docker cp day05-caddy:/data/caddy/pki/authorities/local/root.crt "$work/caddy-root.crt"
echo "With that certificate as the trusted authority, the same request succeeds:"
echo "\$ curl --cacert caddy-root.crt https://$domain"
local_curl --cacert "$work/caddy-root.crt" "https://$domain" | grep -o '<h1>.*</h1>' | sed 's/^/  /'

step "12. The TLS handshake and the certificate (slide 131)"
local_curl -v --cacert "$work/caddy-root.crt" -o /dev/null "https://$domain" 2>&1 |
  grep -E 'SSL connection using|issuer:|expire date:|subjectAltName' | sed 's/^\* */  /' || true
echo "  (Caddy's own certificates are valid for 12 hours and are renewed automatically.)"

step "Done"
echo "https://$domain"
echo "Next, on the Mac: day-05/check-from-mac.sh, then setup/run.sh day-05/verify.sh"

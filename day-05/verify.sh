#!/usr/bin/env bash
# Day 05 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

work=$PWD/.work
ca=$work/caddy-root.crt
domain=${COURSE_DOMAIN:-$(tailscale status --self --peers=false --json | jq -r '.Self.DNSName' | sed 's/\.$//')}
ip4=$(tailscale ip -4)
ip6=$(tailscale ip -6)

zone() { dig +short +time=3 +tries=2 @127.0.0.1 -p 5300 "$@"; }
local_curl() { curl -s -m 5 --resolve "$domain:80:127.0.0.1" --resolve "$domain:443:127.0.0.1" "$@"; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' "$1")" = "true" ]; }
tls_details() { local_curl -v --cacert "$ca" -o /dev/null "https://$domain" 2>&1; }

public_lookup() { [ -n "$(dig +short +time=3 google.com A)" ]; }
root_refers_to_tld() { dig +norecurse +noall +authority +time=3 @i.root-servers.net com NS | grep -q 'gtld-servers.net'; }
tld_refers_to_domain() { dig +norecurse +noall +authority +time=3 @e.gtld-servers.net google.com NS | grep -q 'ns1.google.com'; }
authoritative_answer() { dig +norecurse +time=3 @ns1.google.com google.com A | grep -q 'flags:.* aa'; }

zone_a() { [ "$(zone course.test A)" = "$ip4" ]; }
zone_aaaa() { [ "$(zone course.test AAAA)" = "$ip6" ]; }
zone_cname() { [ "$(zone www.course.test CNAME)" = "course.test." ]; }
zone_mx() { [ "$(zone course.test MX)" = "10 mail.course.test." ]; }
zone_txt() { [ "$(zone course.test TXT)" = '"v=spf1 mx -all"' ]; }
zone_ns() { [ "$(zone course.test NS)" = "ns1.course.test." ]; }
zone_is_authoritative() { dig +time=3 @127.0.0.1 -p 5300 course.test A | grep -q 'flags:.* aa'; }
zone_unknown_name() { dig +time=3 @127.0.0.1 -p 5300 nothing.course.test A | grep -q 'status: NXDOMAIN'; }

domain_points_here() { [ "$(dig +short +time=3 "$domain" A)" = "$ip4" ]; }

http_redirects() {
  local head
  head=$(local_curl -I "http://$domain")
  echo "$head" | grep -qE '^HTTP/[0-9.]+ 30[18]' && echo "$head" | grep -qi "^location: https://$domain"
}
untrusted_is_refused() { ! local_curl -o /dev/null "https://$domain"; }
trusted_serves_site() { local_curl --cacert "$ca" "https://$domain" | grep -qF 'day-05 site'; }
cert_is_for_domain() { tls_details | grep -qE "subjectAltName: .*\"$domain\"|subject: .*CN=$domain"; }
cert_from_caddy_ca() { tls_details | grep -q 'issuer: .*Caddy Local Authority'; }
uses_modern_tls() { tls_details | grep -qE 'SSL connection using TLSv1\.[23]'; }
ca_survives_reruns() { docker volume inspect day05-caddy-data; }

step "Day 05 verification"
echo "DNS resolution (slides 118-126)"
check "a public name resolves" public_lookup
check "a root server refers .com to the gTLD servers" root_refers_to_tld
check "a gTLD server refers google.com to ns1.google.com" tld_refers_to_domain
check "ns1.google.com gives an authoritative answer" authoritative_answer
echo "Our own zone (slide 128)"
check "day05-dns is running" running day05-dns
check "A record: course.test -> $ip4" zone_a
check "AAAA record: course.test -> $ip6" zone_aaaa
check "CNAME record: www.course.test -> course.test" zone_cname
check "MX record" zone_mx
check "TXT record" zone_txt
check "NS record" zone_ns
check "our server answers authoritatively for the zone" zone_is_authoritative
check "a name that is not in the zone gets NXDOMAIN" zone_unknown_name
check "the server's real domain ($domain) resolves to this machine" domain_points_here
echo "HTTPS with Caddy (slides 131-132)"
check "day05-caddy is running" running day05-caddy
check "http:// is redirected to https://" http_redirects
check "without Caddy's root certificate the connection is refused" untrusted_is_refused
check "with Caddy's root certificate, https serves the day 5 site" trusted_serves_site
check "the certificate is issued for $domain" cert_is_for_domain
check "the certificate is issued by Caddy's own authority" cert_from_caddy_ca
check "the connection uses TLS 1.2 or 1.3" uses_modern_tls
check "Caddy's certificate authority is kept in a volume" ca_survives_reruns
summary

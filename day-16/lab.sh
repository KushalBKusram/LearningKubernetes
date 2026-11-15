#!/usr/bin/env bash
# Day 16 lab: a buggy Node.js app behind a Caddy load balancer (slides 316-326).
# Runs on the server. Safe to run more than once: it starts from scratch each time.
#
# Leaves running the compose project "day16":
#   app (x3)   day16-app-1..3, not published
#   caddy      http://localhost:8316 and https://localhost:8317
#   autoheal   restarts unhealthy app containers
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
need_docker

HTTP=http://localhost:8316
HOSTNAME_TLS=day16.test # the name in the Caddyfile; curl is pointed at the server with --resolve

# Every request goes through Caddy. Print how many requests each HTTP status got.
blast() { # blast <count> [parallel]
  seq 1 "$1" | xargs -P "${2:-1}" -I{} curl -s -o /dev/null -m 10 -w '%{http_code}\n' "$HTTP/" | sort | uniq -c | sed 's/^ *\([0-9]*\) \(.*\)/  \1 x HTTP \2/'
}
# Print which instance answered each of N requests, as a count per instance.
who_answers() {
  for _ in $(seq 1 "$1"); do curl -s -m 5 "$HTTP/" | sed -n 's/.*"instance":"\([^"]*\)".*/\1/p'; done | sort | uniq -c | sed 's/^ *\([0-9]*\) \(.*\)/  \2 answered \1 requests/'
}
# Make one instance misbehave by calling it directly, bypassing Caddy.
poke() { # poke <container> <path>
  # A crash ends the container while "docker exec" is still attached, so a non-zero exit is expected.
  docker exec "$1" node -e "fetch('http://127.0.0.1:3000$2').then(r => r.text()).then(t => process.stdout.write('  ' + t)).catch(e => console.log('  ' + e.message))" || true
}
state() { docker inspect -f '{{.State.Status}} / health: {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} / policy restarts: {{.RestartCount}}' "$1"; }
wait_all_healthy() { # wait_all_healthy <seconds>
  local _ c ok
  for _ in $(seq 1 "$1"); do
    ok=1
    for c in day16-app-1 day16-app-2 day16-app-3; do
      [ "$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null)" = "healthy" ] || ok=0
    done
    [ "$ok" = 1 ] && [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$HTTP/health" || true)" = "200" ] && return 0
    sleep 1
  done
  echo "the instances did not all become healthy" >&2
  docker compose ps >&2
  return 1
}

docker compose down --volumes --remove-orphans >/dev/null 2>&1 || true

step "1. Build the image and start everything (slides 317-318, 320)"
run docker compose build
run docker compose up --detach --wait
run docker compose ps
wait_all_healthy 60

step "2. Caddy spreads the requests over three instances (slide 320)"
curl -s -m 5 "$HTTP/"
echo "Twelve requests, who answered:"
who_answers 12

step "3. A crash (slide 322)"
echo "Instance 1 is told to crash. Right after, 30 requests go through Caddy:"
poke day16-app-1 /crash
blast 30
echo "No request failed: Caddy skipped the dead instance, and Docker started it again (restart: unless-stopped)."
sleep 3
echo "day16-app-1 now: $(state day16-app-1)"
wait_all_healthy 60

step "4. A freeze (slide 324)"
echo "Instance 2 is told to freeze. Its process is alive, but it never answers again:"
poke day16-app-2 /freeze
echo "30 requests right away. A request sent to the frozen instance waits 2 seconds, then Caddy retries it elsewhere:"
start=$(date +%s)
blast 30
echo "  took $(( $(date +%s) - start )) seconds in total"
echo "Docker's healthcheck cannot get an answer either, so it marks the container unhealthy:"
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' day16-app-2)" = "unhealthy" ] && break
  sleep 1
done
echo "  day16-app-2: $(state day16-app-2)"
echo "The autoheal container restarts it:"
for _ in $(seq 1 60); do
  docker compose logs autoheal 2>/dev/null | grep -q 'restarting unhealthy container /day16-app-2' && break
  sleep 1
done
docker compose logs --no-log-prefix autoheal | sed 's/^/  /'
wait_all_healthy 60
echo "  day16-app-2: $(state day16-app-2)"
echo "Three healthy instances share the load again. Twelve more requests:"
who_answers 12

step "5. Heavy work is not a freeze (slide 324)"
echo "A 3-second CPU burst on instance 3. It is slow for a moment, then normal:"
poke day16-app-3 '/cpu?seconds=3'
echo "  day16-app-3: $(state day16-app-3)"

step "6. A small benchmark through Caddy (slide 317)"
start=$(date +%s.%N)
blast 300 20
end=$(date +%s.%N)
echo "  300 requests, 20 at a time, in $(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.1f", e - s }') seconds"
who_answers 12

step "7. HTTPS (slide 326)"
echo "Caddy's own certificate authority issued the certificate for $HOSTNAME_TLS. Nothing trusts that"
echo "authority yet, so curl gets -k, and --resolve says where the name lives (there is no DNS entry):"
run curl -sk -m 5 --resolve "$HOSTNAME_TLS:8317:127.0.0.1" "https://$HOSTNAME_TLS:8317/"
tls_out=$(curl -skv -m 5 --resolve "$HOSTNAME_TLS:8317:127.0.0.1" "https://$HOSTNAME_TLS:8317/" 2>&1)
grep -E 'issuer:' <<<"$tls_out" | sed 's/^\*  /  certificate /'

step "8. Surviving a reboot (slide 326)"
for c in day16-app-1 day16-app-2 day16-app-3 day16-caddy-1 day16-autoheal-1; do
  echo "  $c restart policy: $(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c")"
done
echo "With unless-stopped, Docker starts these again when the machine boots."

step "Done"
wait_all_healthy 60
echo "HTTP:  http://$(public_name):8316"
echo "HTTPS: https://$HOSTNAME_TLS:8317 (certificate from Caddy's own CA; needs --resolve, see the README)"
echo "Next: setup/run.sh day-16/verify.sh"

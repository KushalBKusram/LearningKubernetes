# Day 05: Domain, DNS and HTTPS with Caddy

**Status:** run on the server on 2026-11-14; all 22 checks in `verify.sh` pass, and the HTTPS site verifies from the Mac with Caddy's root certificate. A browser shows a certificate warning, which is expected (see "Differences from the slides").

**Slides:** 115-132

## What the slides cover

- What DNS is for (slide 118).
- How a name is resolved: browser and OS cache, resolver, root name server, TLD name server, authoritative name server (slides 119-124).
- Record types: A, AAAA, CNAME, MX, TXT, NS, and the `host` command (slide 126).
- Buying a domain in Route 53 and pointing it at the server (slide 128).
- HTTPS is HTTP over TLS (slide 131).
- Caddy, a web server that sets up HTTPS by itself (slide 132).

## What gets built here

| File | Runs on | What it does |
|---|---|---|
| `lab.sh` | Server | Walks the DNS resolution chain by hand, queries each record type, starts a name server for a practice zone, then serves a site over HTTPS with Caddy. |
| `dns/` | | CoreDNS configuration and the zone file for the practice domain `course.test`. |
| `Caddyfile` | | Caddy's configuration: five lines. |
| `site/` | | The page Caddy serves. |
| `check-from-mac.sh` | Mac | Fetches Caddy's root certificate and checks the redirect and the HTTPS page from the Mac. |
| `verify.sh` | Server | 22 pass/fail checks. |
| `cleanup.sh` | Server | Removes the containers, Caddy's volume and the scratch folder. |

Two containers stay running:

| Container | Ports | What it is |
|---|---|---|
| `day05-dns` | 5300, on the server's localhost only | CoreDNS, authoritative for `course.test` |
| `day05-caddy` | 80 and 443 | Caddy, serving `site/` over HTTPS |

## Run it

From the Mac:

```bash
setup/run.sh day-05/lab.sh
```

```bash
day-05/check-from-mac.sh
```

```bash
setup/run.sh day-05/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 05` on the Mac | `22 passed, 0 failed` |
| 2 | Run `day-05/check-from-mac.sh` on the Mac | A 308 redirect to `https://`, a refusal without the root certificate, then the heading "Served over HTTPS by Caddy" |
| 3 | Open https://<server> in a browser | A certificate warning. After choosing to proceed, the page headed "Served over HTTPS by Caddy" |
| 4 | Open http://<server> (no `s`) | The browser ends up on the `https://` address |

One thing to try yourself: change a DNS record, as you would in Route 53. On the server, add a line to the zone file and copy it into the name server:

```bash
ssh $COURSE_HOST 'cd ~/Projects/Kubernetes/day-05 && echo "shop IN A 192.0.2.50" >> .work/zones/course.test.zone && docker cp .work/zones/. day05-dns:/zones/ && docker restart day05-dns'
```

Then ask for the new name. The answer is `192.0.2.50`:

```bash
ssh $COURSE_HOST 'dig +short @127.0.0.1 -p 5300 shop.course.test'
```

## Differences from the slides

- **The domain.** The slides buy a domain in Route 53 and add an A record for the server. Here the server's name is the one Tailscale already gives it, `<server>`, and Tailscale's DNS holds its A record. Creating records yourself is practised on `course.test`, a zone that only the `day05-dns` container knows about.
- **The certificate.** On the slides Caddy gets a certificate from a public certificate authority, which browsers trust and which needs a server reachable from the internet. Here Caddy acts as its own certificate authority (`tls internal`). The encryption is the same, but nothing trusts Caddy's authority unless told to, so browsers warn. `check-from-mac.sh` tells `curl` to trust it for one request with `--cacert`.
- **Certificate lifetime.** Caddy's own certificates last 12 hours and are renewed automatically. Its certificate authority is kept in the volume `day05-caddy-data`, so re-running the lab does not create a new one. Volumes are covered on day 13.
- **How the files get in.** The container is made with `docker create`, the `Caddyfile` and the site are copied in with `docker cp`, and then it is started. That uses days 2 and 4 instead of a bind mount.

## Two optional ways to get rid of the browser warning

Neither has been done. Both are your decision.

**Trust Caddy's authority on this Mac.** This changes a security setting of the Mac: it will then trust any certificate issued by this Caddy. `check-from-mac.sh` saves the root certificate as `day-05/caddy-root.crt`.

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain day-05/caddy-root.crt
```

**Use a real, publicly trusted certificate.** The tailnet has HTTPS certificates enabled, so Caddy could fetch a Let's Encrypt certificate for the Tailscale name through Tailscale. That is the closest match to the slides. The cost is that the name `<server>` is then recorded permanently in the public Certificate Transparency logs. It is not set up here and has not been tested.

## Without AWS

| On the slides | Here |
|---|---|
| Route 53 domain registration | The server's Tailscale name |
| Route 53 hosted zone with DNS records | CoreDNS container with the zone `course.test` |
| Public certificate authority | Caddy's internal certificate authority |

# Day 16: A buggy Node.js app behind a load balancer

**Status:** run on the server on 2026-11-14, twice (the lab is repeatable); all 16 checks in `verify.sh` pass, including a real crash and a real freeze that the setup survives. Ready for you to validate.

**Slides:** 316-326

## What the slides cover

- The goal: deploy an app that can crash, freeze, or use a lot of CPU, anyway (slide 317).
- The answer: several instances of the app, and one Caddy in front as reverse proxy and load balancer (slides 317-320).
- A **crash** (the process exits, the container stops): a restart policy brings the container back, and Caddy stops using it meanwhile (slide 322).
- A **freeze** (the process is alive but never answers) is harder to spot, and not the same as heavy work that takes a few seconds. Caddy retries on another instance after a short timeout; Docker adds a healthcheck plus auto-healing (slide 324).
- Benchmarking the setup, and running it in production with HTTPS (slide 317).
- Exercise: deploy it on your own server so that it comes back after a reboot; port 80 and 443 exposed; HTTPS only with your own domain (slide 326).

## What gets built here

| File | What it does |
|---|---|
| `app/server.js` | The app, no dependencies. `/` says which instance answered, `/health` answers `ok`, `/crash` exits the process, `/freeze` blocks it forever, `/cpu?seconds=N` burns CPU for N seconds. |
| `app/Dockerfile` | Builds the image `day16-bad-app` with a `HEALTHCHECK`, running as the non-root user `node`. |
| `compose.yaml` | Three app replicas, Caddy, and a small auto-heal container. |
| `Caddyfile` | Round-robin over the three instances, retries, an active `/health` check every 2 seconds, HTTP and HTTPS. |
| `lab.sh` | Starts everything, then shows round-robin, a crash, a freeze, a CPU burst, a small benchmark and HTTPS. |
| `verify.sh` | 16 pass/fail checks. It crashes and freezes an instance on purpose, as the lab does. |
| `cleanup.sh` | Takes the project down and removes the image. |

Left running after the lab (compose project `day16`):

| Container | Port | What |
|---|---|---|
| `day16-app-1`, `-2`, `-3` | none | the three instances, restart policy `unless-stopped` |
| `day16-caddy-1` | 8316 (HTTP), 8317 (HTTPS) | the load balancer |
| `day16-autoheal-1` | none | restarts unhealthy app containers |

### How the failures are handled

| Failure | What detects it | What fixes it |
|---|---|---|
| Crash | Caddy gets "connection refused" and tries another instance within 250 ms; its health check marks the instance down | Docker restarts the container (`restart: unless-stopped`) |
| Freeze | Caddy waits at most 2 seconds for an answer, then retries the GET on another instance; Docker's healthcheck also fails and marks the container `unhealthy` | `autoheal` restarts the unhealthy container |
| Heavy work | Nothing: a few seconds of CPU is slow, not broken, and the healthcheck tolerates it | Nothing needed |

Timing of a freeze, as measured on the server: the container turns `unhealthy` after about 10 seconds (three failed checks, 3 seconds apart), autoheal restarts it, and all three instances answer again about 25 to 30 seconds after the freeze. Nobody sees an error in between, because the other two instances take all the traffic.

## Run it

From the Mac:

```bash
setup/run.sh day-16/lab.sh
```

```bash
setup/run.sh day-16/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 16` on the Mac | `16 passed, 0 failed` |
| 2 | Open http://<server>:8316 and reload several times | JSON with an `instance` value that changes between three ids |
| 3 | Run `ssh $COURSE_HOST "cd ~/Projects/Kubernetes/day-16 && docker compose ps"` | Three `app` containers `(healthy)`, plus caddy and autoheal |
| 4 | Read steps 3 and 4 of the lab output | `30 x HTTP 200` after the crash and again after the freeze |

Things to try yourself.

**Crash one instance and watch the page.** Keep reloading http://<server>:8316 in a browser while you run this. You should never see an error:

```bash
ssh $COURSE_HOST "docker exec day16-app-1 node -e \"fetch('http://127.0.0.1:3000/crash')\""
```

Then look at what Docker did (the restart counter goes up by one):

```bash
ssh $COURSE_HOST "docker inspect -f '{{.Name}} restarts={{.RestartCount}}' day16-app-1"
```

**Freeze one instance and watch it get healed.** Run this, then watch the status for about 10 to 20 seconds: `healthy`, then `unhealthy`, then `healthy` again once autoheal has restarted it.

```bash
ssh $COURSE_HOST "docker exec day16-app-2 node -e \"fetch('http://127.0.0.1:3000/freeze')\""
```

```bash
ssh $COURSE_HOST "watch -n 2 'docker ps --filter name=day16-app --format \"{{.Names}} {{.Status}}\"'"
```

**HTTPS.** The name `day16.test` has no DNS entry, so tell curl where it lives. From the Mac:

```bash
curl -k --resolve day16.test:8317:$(dig +short $SERVER | head -1) https://day16.test:8317/
```

`-k` is needed because nothing trusts Caddy's own certificate authority.

## Differences from the slides

- The slides' app is called `bad-app` and is given as a download with its own `Dockerfile`. This one is written from the slides' description (crash, freeze, CPU), has no `node_modules`, and offers the endpoints above so each failure can be triggered on demand.
- Three instances, as in the slides' architecture. They are `deploy: replicas: 3` in `compose.yaml`, which Compose runs as three containers.
- **Auto-healing** (slide 324) is a small container built from the official `docker:cli` image with a six-line shell loop you can read in `compose.yaml`. Docker never restarts an unhealthy container by itself, and the usual solution needs the Docker socket. **Mounting the Docker socket gives that container full control of Docker on the machine.** It is limited here to containers of this project that carry the label `autoheal=true`, and `verify.sh` checks that no other container has the socket. Remove the `autoheal` service from `compose.yaml` if you would rather not have it.
- **HTTPS (slide 326)**: the slides use a purchased domain and a public certificate. Without one, Caddy's own certificate authority (`tls internal`) issues a certificate for the made-up name `day16.test`. The name cannot be a `*.ts.net` name: Caddy sends those to Tailscale's certificate service, which a container cannot reach, and the handshake fails.
- **Keep-alive is off** between Caddy and the app (`keepalive off` in the Caddyfile). With it on, Caddy kept a pooled connection to the frozen process, and after autoheal restarted the container Caddy took about 30 extra seconds to use it again (found while testing). Turning it off costs a little speed, which does not matter here.
- The Docker healthcheck is a few lines of bash, not a Node script. The first version started a new Node process every 3 seconds, which on a busy machine sometimes ran past the time limit and made healthy instances look unhealthy.
- Ports: the slides use 80 and 443. Here they are 8316 and 8317, because ports 80 and 443 belong to day 5.
- The slides' benchmark tool is not named in the text I could read. The lab sends 300 requests, 20 at a time, with `curl` and `xargs`; the result (about a third of a second) says little more than that the balancer is not the bottleneck.
- The reboot test of slide 326 needs a reboot, which needs sudo. The lab shows that the restart policy is `unless-stopped` on every container. What that policy does when the daemon starts again is tested without a reboot by `day-03/boot-test.sh` (see day 3); a real reboot is left to you.

## Without AWS

Caddy takes the place of the load balancer and certificate service that AWS would provide for this setup (an Application Load Balancer and Certificate Manager). Day 18 uses the same idea for ECS.

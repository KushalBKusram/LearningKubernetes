# Day 18: ECS part 2: storage, load balancer, HTTPS, WordPress

**Status:** run on the server on 2026-11-14, twice; all 23 checks in `verify.sh` pass, and `from-mac.sh` loads both sites over HTTPS and uploads over SFTP from the Mac. Validated.

**Slides:** 338-356

## What the slides cover

- EFS: one file system that many instances mount at the same time (slide 339).
- Putting the application itself on EFS and mounting it into the PHP containers (slide 341).
- Transfer Family: an SFTP server in front of EFS, billed by the hour, to be turned off after use (slide 342).
- Mounting the EFS volume through the task definition (slide 344).
- An application load balancer, which also takes care of HTTPS, and its target group, which the service keeps up to date (slides 346-347).
- A subdomain pointing at the load balancer, then HTTPS with a certificate (slides 349-351).
- Project 2: WordPress on ECS, with the database on Amazon RDS because a database does not scale like a stateless service (slide 353).
- Docker retrospective and practice test (slides 355-356).

## Without AWS

| AWS on the slides | Here |
|---|---|
| ECS cluster and services | The Swarm cluster from day 17, stack `day18` |
| EFS volume | A named Docker volume, `day18-efs`, mounted by every task |
| Transfer Family (SFTP) | `day18-sftp`, a small SFTP-only server built on the official `ubuntu` image |
| Application Load Balancer | Caddy, service `day18_lb` |
| Target group | The cluster's DNS list of the service's tasks, which Caddy re-reads every 5 seconds |
| Certificate Manager | Caddy's internal certificate authority (`tls internal`) |
| VPC and security groups | The overlay network `day18-net`; only the load balancer publishes ports |
| Amazon RDS | `day18-rds`, a MariaDB container outside the stack |

What this does not give you:

- **A real network file system.** The volume is a folder on the server's disk. It shows the behaviour that matters here (many tasks, one set of files), but it would not span several servers the way EFS does. An NFS-backed volume was not possible without sudo: the kernel's NFS server module is not loaded.
- **A managed database.** `day18-rds` has no backups, failover or patching.
- **A subdomain and a public certificate.** See "Differences from the slides".

## What gets built here

| File | Runs on | What it does |
|---|---|---|
| `app/` | | The upload form from slide 329: PHP, no database, pictures stored in `uploads/`. |
| `sftp/` | | Dockerfile and configuration for the SFTP server. |
| `lb/` | | Dockerfile and `Caddyfile` for the load balancer. |
| `stack.yaml` | | Project 1: the `php` service (official image, 2 tasks, mounts the volume) and the `lb` service. |
| `stack-wordpress.yaml` | | Project 2: adds the `wordpress` service to the same stack. |
| `lab.sh` | Server | Builds everything in the slides' order. 11 steps. |
| `from-mac.sh` | Mac | Loads both sites over HTTPS, and uploads a picture over SFTP, from the Mac. |
| `verify.sh` | Server | 23 pass/fail checks. |
| `cleanup.sh` | Server | Removes everything day 18 created. |

Ports on the server:

| Port | What answers |
|---|---|
| 8543 | HTTPS, the upload form |
| 8544 | HTTPS, WordPress |
| 8580 | HTTP, redirects to 8543 |
| 8522 | SFTP, only while `day18-sftp` is started |

## Run it

From the Mac:

```bash
setup/run.sh day-18/lab.sh
```

```bash
setup/run.sh day-18/verify.sh
```

```bash
day-18/from-mac.sh
```

Every run of `lab.sh` starts from scratch: uploaded pictures and the WordPress site are wiped and rebuilt.

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 18` on the Mac | `23 passed, 0 failed` |
| 2 | Run `day-18/from-mac.sh` on the Mac | Titles "Day 18: memories" and "Day 18 blog", a `301` to port 8543, and `200 image/png` for the picture uploaded over SFTP |
| 3 | Open https://<server>:8543 | A certificate warning first (see below), then the "Memories" page with the stored pictures. Reload: the task name changes, the pictures stay |
| 4 | Open https://<server>:8544 | After the same warning, the "Day 18 blog" WordPress site |
| 5 | Run `ssh $COURSE_HOST docker service ls` | `day18_php 2/2`, `day18_lb 1/1`, `day18_wordpress 2/2`, and ports only on `day18_lb` |

**About the certificate warning.** The certificate comes from Caddy's own certificate authority, which your browser does not know. `from-mac.sh` checks the certificate properly, against that authority's certificate, without changing anything on the Mac. In the browser you can either accept the warning or decide to trust the authority yourself; its certificate is `day-18/.work/root.crt` on the server.

Two things to try yourself.

**Upload a picture in the browser.** Use the form on port 8543. The picture appears in the gallery and stays there on every reload, whichever task answers. That is slide 329's point: the files are not inside any one container.

**Log in to WordPress.** Go to https://<server>:8544/wp-login.php. The user is `admin`. The password was generated by the lab and is only on the server:

```bash
ssh $COURSE_HOST cat Projects/Kubernetes/day-18/.work/wp-admin-password
```

Write a post, then reload the front page a few times. Both WordPress tasks show it, because the content is in the one database and the files are on the one shared volume.

## Differences from the slides

- **Order of the two days.** The slides deploy the PHP container first and add EFS afterwards. Here day 17 covers the deployment itself, and day 18 starts with the storage.
- **No subdomain (slide 349).** The slides point `memories.docker-test.click` at the load balancer. Without a domain to manage, the two projects are told apart by port on the server's Tailscale name: 8543 and 8544.
- **Ports.** 80 and 443 belong to day 5, so the load balancer uses 8543, 8544 and 8580, and the redirect from HTTP is written out in the `Caddyfile`.
- **Certificate.** Issued by Caddy's own authority and valid for 12 hours at a time; Caddy renews it by itself. A public certificate needs a public domain.
- **Database placement.** As on the slides, the database is not a service of the cluster. It is a plain container on the same network, which is as close to "outside, but reachable" as one machine allows.
- **WordPress starts with one task.** The first task fills the empty shared volume with WordPress' files. The lab adds the second task after the site is installed, so two tasks never write the same files at once.
- **WordPress is installed by the lab**, through the installer's own form, so that the checks have a finished site to look at. On the slides you click through the installer.
- **The upload form checks what it stores.** Only JPEG, PNG, GIF and WebP are accepted, judged by content, and uploaded files can never run as PHP.

## State on the server

- Stack `day18` (5 tasks), the container `day18-rds`, and the stopped container `day18-sftp`.
- Ports 8543, 8544 and 8580 are open on every network interface of the server, not only Tailscale. The upload form accepts pictures from anyone who can reach port 8543.
- The generated passwords are in `day-18/.work` on the server only (folder readable by your user only). They are not in this repository.

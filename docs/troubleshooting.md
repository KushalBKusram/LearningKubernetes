# Problems met while building this, and what fixed them

These all happened for real while building the 25 days. Each entry says what you see, why, and what the labs do about it.

## Docker Hub

**An image pull fails with an IPv6 "network is unreachable" or route error.** Seen once, on the first `docker pull` of `registry:2`. A retry worked. The day 10 lab retries pulls for this reason. If it keeps happening, check that the server's IPv6 route works, or disable IPv6 for Docker.

**Pulls start failing with "toomanyrequests".** Docker Hub limits anonymous pulls per IP address. The labs avoid pulling an image that is already present and never use `--pull always`. If you hit the limit, wait, or log in with `docker login`.

## Kubernetes (kind)

**`kube-proxy` or the storage provisioner crash-loops with "too many open files" or `fsnotify watcher init`.** Each `kind` node needs inotify instances, and Ubuntu's default limit of 128 per user runs out with two clusters (four nodes) plus other containers. Services stop working on the affected node. Raise the limits on the server (needs sudo):

```bash
sudo sysctl fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288
```

To keep them after a reboot:

```bash
printf 'fs.inotify.max_user_instances=512\nfs.inotify.max_user_watches=524288\n' | sudo tee /etc/sysctl.d/99-kind.conf
```

Days 19-23 use a single-node cluster, which needs far fewer instances, but the limit can still be reached when many containers start at once. Once it was, and a restart of the crashed add-ons fixed it, so `day-19/k8s-lib.sh` does that automatically (`ensure_cluster_healthy`). Days 24-25 add a second, three-node cluster and need the raised limits.

**`kind load docker-image` fails with "content digest ... not found".** This happens when Docker keeps a multi-platform image. `day-19/k8s-lib.sh` and `day-24/env.sh` load images with `docker save --platform ...` and `kind load image-archive` instead.

**The Kubernetes Dashboard.** Its repository was archived in January 2026, so day 19 uses Headlamp.

**`ingress-nginx`.** It was retired in March 2026, so day 24 uses the F5 NGINX Ingress Controller. Its chart defaults to `externalTrafficPolicy: Local`, under which only the node running the controller answers on the NodePort. The lab sets `Cluster`.

**A `LoadBalancer` address is not reachable from your computer.** With MetalLB the address exists only on the server's Docker network. Day 24 publishes host ports for the Mac-facing paths.

## Scripts

**A check fails only sometimes, with `curl ... | grep -q`.** Under `set -o pipefail`, `grep -q` exits as soon as it matches, `curl` then gets a broken pipe and the pipeline reports failure. The checks capture the output first and then search it. If you write new checks, do the same.

## Caddy

**Browsers warn about the certificate.** Without a public domain, Caddy issues certificates from its own authority (`tls internal`), which no browser trusts. `day-05/check-from-mac.sh` shows the verified path with `curl --cacert`.

**A `*.ts.net` site name gave a TLS "internal error" on day 16,** so that day uses the made-up name `day16.test` and points `curl` at the server with `--resolve`. Day 5 serves the Tailscale name with `tls internal` without this problem. The difference was not investigated.

## The AWS mock (moto, days 8, 11, 12)

- `moto` stores IAM users, policies and roles, but it does not enforce permissions the way AWS does.
- It checks the action of a request but not EC2 resource ARNs, so a policy limited to one instance is not honoured for EC2. Resource checks do work for S3.
- A user can only assume a role if the role's trust policy names that user. Otherwise `assume-role` fails with a server error.

## After a reboot

Docker starts at boot, and every container the labs leave running has the restart policy `unless-stopped`, so they come back. `day-03/boot-test.sh` tests this without a reboot by restarting a nested Docker daemon. A real reboot has not been tried. If a `kind` cluster does not come back cleanly, delete and recreate it with `day-19/lab.sh` or `day-24/lab.sh`.

# Docker, Kubernetes and AWS in 25 days: a hands-on build

Working scripts for each day of a Docker, Kubernetes and AWS deployment course, one folder per day. Each day has a lab that runs the course's commands, checks that prove the result, and a README that says what was built and how to look at it yourself.

**No AWS account is needed.** Everything that the course does on AWS (EC2, ECR, App Runner, ECS, EKS, S3, IAM, Route 53, load balancers) is replaced by something that runs on one Linux server you control. The replacements and their limits are listed [below](#what-replaces-aws).

## About this repository

This is a learning project. It follows an online course, "Docker, Kubernetes & AWS: Real-World Deployment in 25 Days", by following its slides. The repository contains my own scripts, manifests and notes. It does not contain the course's slides, videos or other material, and it is not affiliated with the course or its author. To get the explanations behind the steps, take the course itself.

The 25-day split is my own pacing. The slides do not give a day-by-day schedule.

## What you need

- **A Linux server you can reach over SSH.** Everything runs there. It was built and tested on Ubuntu 26.04 (x86_64) with 12 CPU threads and 14 GB of RAM. Any recent Ubuntu or Debian should work. A machine at home or a virtual machine is fine. A cloud server works too, but then the lab ports are open to the internet unless you restrict them.
- **sudo, once,** to install Docker (`setup/install-docker.sh`) and to raise two kernel limits for days 24-25.
- **Your own computer** with `ssh`, `scp` and `rsync`. The docs call it "the Mac". Nothing from the labs runs on it.
- **Tailscale is optional.** Days 5 and 18 build an HTTPS site for the server's name, and the labs print URLs with it. With Tailscale the name is found automatically (`<machine>.<tailnet>.ts.net`). Without it, set `COURSE_DOMAIN` to the name your browser uses to reach the server. A few places also read the server's Tailscale addresses directly (`tailscale ip`): the zone file in day 5, and the checks in days 22 and 23. On a server without Tailscale those lines would need replacing; that has not been tried.

## Quick start

1. **Point the scripts at your server.** Add the server to `~/.ssh/config` so that `ssh my-server` works without a password prompt, then:

   ```bash
   cp setup/local.env.example setup/local.env
   ```

   Edit `setup/local.env` and set `COURSE_HOST` to your SSH name. The file is not committed.

2. **Copy the project to the server and install Docker there.** The installer needs your sudo password, so run it in a terminal:

   ```bash
   setup/sync.sh
   ```

   ```bash
   ssh -t my-server 'bash ~/Projects/Kubernetes/setup/install-docker.sh'
   ```

3. **Run a day and check it.** From your computer:

   ```bash
   setup/run.sh day-01/lab.sh
   ```

   ```bash
   setup/validate.sh 01
   ```

4. **Before day 19,** install `kubectl`, `kind` and `helm` on the server. No sudo needed:

   ```bash
   setup/run.sh setup/install-k8s-tools.sh
   ```

   Before day 24, raise the kernel limits on the server (see [Resources and ports](#resources-and-ports)).

To use the commands in the day READMEs as written (`ssh $COURSE_HOST ...`, `curl http://$SERVER:8888`), load the two variables into your shell first:

```bash
source setup/env.sh
```

In the READMEs, `<server>` means the name or address your browser uses to reach the server.

## How each day is laid out

| File | What it is |
|---|---|
| `README.md` | The slides covered, what gets built, how to run it, **how to validate** (what to open and what you should see, plus one or two things to try by hand), differences from the slides, and what replaces AWS. |
| `lab.sh` | Runs the day's commands on the server, one numbered step per slide topic, printing each command first. Safe to run twice. |
| `verify.sh` | Pass/fail checks of the result. Ends with `N passed, M failed`. |
| `cleanup.sh` | Removes what the day created. Where it deletes data (volumes, databases), its README says so. Day 1 has none (its lab removes its own containers) and day 25 has `teardown.sh`, which deletes the cluster. |
| other files | The app, Dockerfile, manifests or configuration the day uses. |

`setup/validate.sh` with no argument runs every day's `verify.sh` and prints one line per day. Every name a day creates starts with its day (`day05-caddy`, `day13-mariadb-vol`), so days do not collide and cleanup only touches its own.

## The 25 days

| Day | Topic | Slides | Checks |
|---|---|---|---|
| [01](day-01/README.md) | Containers, images and first runs | 1-24 | 9 |
| [02](day-02/README.md) | Managing containers and running nginx | 25-55 | 6 |
| [03](day-03/README.md) | Docker on a Linux server | 56-97 | 7, plus 13 in `boot-test.sh` |
| [04](day-04/README.md) | Getting files into containers | 98-114 | 14 |
| [05](day-05/README.md) | Domain, DNS and HTTPS with Caddy | 115-132 | 22 |
| [06](day-06/README.md) | App Runner and Dockerfiles | 133-157 | 21 |
| [07](day-07/README.md) | Your own registry and CPU architectures | 158-168 | 21 |
| [08](day-08/README.md) | AWS crash course and IAM | 169-196 | 17 |
| [09](day-09/README.md) | Git, GitHub, ECR and automated image builds | 197-215 | 27 |
| [10](day-10/README.md) | Smaller, safer images | 216-231 | 32 |
| [11](day-11/README.md) | Networking in AWS | 232-247 | 22 |
| [12](day-12/README.md) | Full-stack deployment (optional chapter) | 248-264 | 18 |
| [13](day-13/README.md) | Volumes | 265-281 | 11 |
| [14](day-14/README.md) | Docker networking | 282-300 | 17 |
| [15](day-15/README.md) | Docker Compose | 301-315 | 17 |
| [16](day-16/README.md) | A buggy Node.js app behind a load balancer | 316-326 | 16 |
| [17](day-17/README.md) | ECS part 1: tasks, clusters, services | 327-337 | 13 |
| [18](day-18/README.md) | ECS part 2: storage, load balancer, HTTPS, WordPress | 338-356 | 23, plus a check from your computer |
| [19](day-19/README.md) | Kubernetes: first cluster | 357-384 | 17 |
| [20](day-20/README.md) | Pods in YAML, Deployments and labels | 385-403 | 14 |
| [21](day-21/README.md) | StatefulSets, configuration and Secrets | 404-441 | 16 |
| [22](day-22/README.md) | Kubernetes networking: Services | 442-467 | 21 |
| [23](day-23/README.md) | Kubernetes storage | 468-497 | 22 |
| [24](day-24/README.md) | EKS part 1: cluster, load balancers, Ingress, HTTPS | 498-533 | 20 |
| [25](day-25/README.md) | EKS part 2: storage, availability zones, teardown | 534-550 | 17 |

### What each day does

**Docker basics (days 1-5)**

- **Day 1** runs the first containers (`hello-world`, Ubuntu, Fedora, Python, Node) and shows what an image, a tag and a layer are. It proves that a file written in a container is not in the image, and that `docker run` is a pull, a create and a start.
- **Day 2** runs nginx: published ports, detached mode, names, logs, stop and start, `exec`, `docker create`, `--rm`. It ends with the exercise of changing nginx's start page, done with `sed` so that it can run unattended.
- **Day 3** treats the server as the machine to run Docker on: client and daemon, the official install, and restart policies. Apache runs with `--restart unless-stopped` and the lab ends its process to show Docker restarting it. `boot-test.sh` tests "comes back on boot" without a reboot, by restarting a nested Docker daemon.
- **Day 4** gets files into containers: `docker cp` in both directions (also while stopped), bind mounts with `-v` and `--mount`, read-only mounts. A small website is deployed the way the slides do it, with `scp` to the server and then `docker cp` into the container, next to a second container that serves the same site from a bind mount.
- **Day 5** walks the DNS chain by hand (root server, `.com` server, authoritative server), queries each record type, and runs a CoreDNS container as the authoritative server for a practice domain, `course.test`. It then serves a site over HTTPS with Caddy and shows the redirect, the certificate, and what happens to a client that does not trust Caddy's authority.

**Images, registries and AWS basics (days 6-12)**

- **Day 6** writes a small Node.js app with its own Dockerfile and runs it as a stateless container, standing in for App Runner. Separate demos show `CMD`, `ENTRYPOINT`, and `COPY` versus `ADD`. Days 7, 9 and 10 reuse this app.
- **Day 7** runs a private registry with a password, pushes and pulls the day 6 image through it, and covers CPU architectures: `--platform`, and a multi-platform build for amd64 and arm64.
- **Day 8** practises IAM with the real AWS CLI against `moto`, a mock of the AWS APIs: regions, users, a policy limited to one resource, a managed policy, a role, and temporary credentials.
- **Day 9** covers Git: commits, branches and a merge. A bare repository stands in for GitHub, and a `post-receive` hook builds each push to `main`, tags the image with the commit hash, pushes it to the day 7 registry and replaces the running container.
- **Day 10** compares one app built on Debian, slim and Alpine bases, shows the musl-versus-glibc pitfalls, builds a TypeScript app in one stage and in two, and adds a `HEALTHCHECK` whose status goes from starting to healthy to unhealthy and back.
- **Day 11** builds a public and a private network layout in Docker (an `--internal` network as the private subnet) and proves who can reach whom. It then makes the matching VPC, subnet, route table and security-group API calls against `moto`.
- **Day 12** (an optional chapter in the slides) is a full-stack notes app: a React frontend built with esbuild and uploaded to an S3-compatible bucket, a Node.js API, MongoDB, and Caddy in front of them as the CloudFront stand-in.

**Docker in depth (days 13-18)**

- **Day 13** is about volumes: named volumes, `--mount` and `-v`, automatic volumes, `VOLUME` in a Dockerfile. MariaDB 10.11 writes three rows, is replaced by the latest MariaDB on the same volume, and reads them back.
- **Day 14** covers the default bridge, host and none networks, and custom networks with name resolution. It ends with the slides' task: MongoDB and mongo-express on one network, finding each other by name.
- **Day 15** moves a multi-container setup into Docker Compose: WordPress and MariaDB with healthchecks, `depends_on`, named volumes and a generated `.env`.
- **Day 16** runs a deliberately buggy Node.js app (it can crash, freeze or burn CPU on request) as three instances behind Caddy, with round-robin, active health checks and an auto-heal container. The lab and its checks crash and freeze an instance and show recovery.
- **Day 17** uses single-node Docker Swarm as the stand-in for ECS: a stack file as the task definition, a service with replicas, a killed task being replaced, scaling, and a rolling update from v1 to v2 while requests keep being answered.
- **Day 18** continues with a shared volume (EFS stand-in), an SFTP container to upload into it (Transfer Family stand-in), Caddy as the load balancer with HTTPS, and then WordPress with its database kept outside the stack, like RDS.

**Kubernetes (days 19-23)** runs on a single-node `kind` cluster called `course`.

- **Day 19** creates the cluster and covers `kubectl`, the control plane, a first pod, restart policy and Helm, with Headlamp as the dashboard.
- **Day 20** writes pod manifests and compares ReplicaSets and Deployments with WordPress, using labels, scaling, a rolling update and a rollback. Jobs and DaemonSets run briefly.
- **Day 21** covers StatefulSets (sticky names, ordering), environment variables, Secrets, and your own image loaded into the cluster, with each `imagePullPolicy`.
- **Day 22** covers Services: ClusterIP, cluster DNS, NodePort, and the three port numbers. WordPress reaches MariaDB by Service name, and the page keeps loading when a pod is deleted.
- **Day 23** covers storage: `emptyDir` and `hostPath`, then StorageClass, PersistentVolume and PersistentVolumeClaim built by hand, claims that cannot bind and why, access modes, and `volumeClaimTemplates` for MariaDB.

**EKS stand-in (days 24-25)** runs on a three-node `kind` cluster called `eks`, with its nodes labelled as two availability zones.

- **Day 24** replaces `eksctl` with a cluster config file. It exposes nginx through a NodePort, a LoadBalancer Service (MetalLB) and an Ingress with HTTPS (F5 NGINX Ingress Controller), builds a custom image, and makes a load balancer by hand.
- **Day 25** puts WordPress and MySQL on that cluster with two kinds of storage: a shared volume (`ReadWriteMany`, the EFS stand-in) and a local volume tied to one node (`ReadWriteOnce`, the EBS stand-in). A pod that claims the database volume but must run in the other zone stays `Pending`, which is the slides' EBS-and-zones point. `teardown.sh` deletes the cluster.

## What replaces AWS

| AWS service on the slides | Replacement on your server | Day |
|---|---|---|
| EC2 (a rented Ubuntu server) | The server itself, reached over SSH | 3 |
| Route 53 domain | The server's Tailscale name, or `COURSE_DOMAIN` | 5 |
| Route 53 hosted zone | A CoreDNS container with the zone `course.test` | 5 |
| Public HTTPS certificate | Caddy's own certificate authority | 5, 16, 18, 24 |
| App Runner | A stateless container with a restart policy | 6, 9 |
| ECR | A private `registry:2` container | 7, 9 |
| IAM, the AWS CLI | `moto`, an open-source mock of the AWS APIs | 8, 11 |
| VPC, subnets, security groups | Docker networks (one `--internal`), published ports; API calls against `moto` | 11 |
| S3, CloudFront | An S3-compatible `moto` bucket, with Caddy in front | 12 |
| DocumentDB | A MongoDB container | 12 |
| ECS | Docker Swarm services and stack files | 17, 18 |
| EFS, Transfer Family | A shared named volume, an SFTP container | 18 |
| RDS | A MariaDB container outside the stack | 18 |
| Application Load Balancer | Caddy | 16, 18 |
| EKS, `eksctl` | `kind` clusters from config files | 19, 24 |
| AWS load balancers for Kubernetes | MetalLB, and a hand-made nginx load balancer | 24 |
| AWS Load Balancer Controller | F5 NGINX Ingress Controller | 24 |
| EFS volumes in Kubernetes | An in-cluster NFS provisioner (`ReadWriteMany`) | 25 |
| EBS volumes, availability zones | The local-path provisioner (`ReadWriteOnce`, one node); zone labels on the nodes | 25 |

### What the stand-ins cannot teach

- The AWS console, and where to click in it.
- Real IAM enforcement. `moto` stores users, policies and roles, but does not deny requests the way AWS does, and it does not check EC2 resource ARNs.
- Billing, the free tier and cost control.
- A site reachable from the public internet under a domain you bought, with a publicly trusted certificate.
- Real multi-zone behaviour. The zones on day 24 are labels on three nodes that are all on one machine.
- AWS-specific behaviour of managed services, such as App Runner autoscaling, EKS upgrades or EFS performance.
- A real NFS file system for the EFS stand-in on day 18. The server's kernel NFS module needs sudo, so day 18 uses a shared named volume.

## Resources and ports

**Memory and CPU.** With every day's workloads left running at once, the whole project used roughly 6 GB of a 14 GB machine. Running one day at a time needs far less. The Kubernetes days are the heaviest: the `eks` cluster is three nodes.

**Kernel limits for days 24-25.** Two `kind` clusters (four nodes) exceed Ubuntu's default inotify limit of 128 instances. Raise it on the server (needs sudo):

```bash
sudo sysctl fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288
```

To keep it after a reboot:

```bash
printf 'fs.inotify.max_user_instances=512\nfs.inotify.max_user_watches=524288\n' | sudo tee /etc/sysctl.d/99-kind.conf
```

**Ports.** Each day publishes ports on the server. Make sure none of them is in use:

| Day | Ports on the server |
|---|---|
| 2 | 8888 (8889 briefly) |
| 3 | 8080 |
| 4 | 8081, 3000 |
| 5 | 80, 443; 5300 on localhost only |
| 6 | 8101 |
| 7 | 5000 on localhost only |
| 8 | 8200 |
| 9 | 8109 |
| 10 | 8110 |
| 11 | 8211 |
| 12 | 8212 |
| 13 | 8313 |
| 14 | 8314 (8315 briefly) |
| 15 | 8325 |
| 16 | 8316 (HTTP), 8317 (HTTPS) |
| 17 | 8500 |
| 18 | 8543, 8544, 8580; 8522 for SFTP only while it is switched on |
| 19-23 | 30080-30089, published by the `course` cluster: 30089 is the dashboard, 30080 and 30081 are day 22, 30082 is day 23 |
| 24 | 8430, 8431, 8440, 8443, 8480 |
| 25 | 8450 |

## Safety notes

These labs are for a machine you own and can afford to experiment on.

- **Ports are open on every network interface.** Docker publishes a port on all of the server's addresses, not only the Tailscale one. Anything on the server's network can reach the lab pages. Do not run this on a server exposed to the internet without a firewall in front of it.
- **The labs use throwaway credentials.** Where a password is needed, a lab either generates a random one into a `.work/` folder on the server (days 7, 13, 15, 18) or uses an obviously fake value in the manifest (days 8, 11, 21, 22, 23, 25). Do not reuse any of these.
- **Day 16's auto-heal container mounts the Docker socket,** which gives it full control of Docker on the server. It is limited to its own project's containers by its script, and a check confirms no other container has the socket. Remove the `autoheal` service from `day-16/compose.yaml` if you would rather not have it.
- **Day 7 stores a registry login** for `localhost:5000` in `~/.docker/config.json` on the server, unencrypted. The registry listens on localhost only.
- **Day 3's `boot-test.sh` starts a privileged container** (`docker:dind`) for about a minute, to restart a nested Docker daemon. It removes it afterwards.
- **Adding your user to the `docker` group** (done by `install-docker.sh`) gives that user root-equivalent access to the machine.
- **Some cleanup scripts delete data.** Days 13, 14, 15 and 18 remove volumes and the data in them. Their READMEs say so.

## Status and what is not verified

Every day was run on one Ubuntu 26.04 server and its `verify.sh` passes (about 440 checks in all). A final run of every day's checks, one after another, passed in full. The following has **not** been verified:

- **Day 12 in a real browser.** The pages and the API answer correctly, and the built page was exercised in a scripted browser, but it has not been looked at in a normal browser.
- **A real reboot.** `day-03/boot-test.sh` tests restart-on-boot by restarting a nested Docker daemon, and `docker.service` is enabled at boot. The server itself was not rebooted, and nothing was tested about the `kind` clusters coming back after one.
- **The `apt` steps on day 3** (`apt upgrade`, installing `cowsay`). They need sudo and change the whole machine, so they are left to you.
- **Browsers show a certificate warning** on the HTTPS pages (days 5, 16, 18, 24), because the certificates come from local authorities. The checks verify them with `curl --cacert` instead.
- **Servers other than the one used here.** Other distributions, ARM servers and servers without Tailscale have not been tried.

Known problems and their fixes are in [docs/troubleshooting.md](docs/troubleshooting.md). How the pieces fit together is in [docs/architecture.md](docs/architecture.md).

## Cleaning up

Each day has a `cleanup.sh` that removes only what that day created:

```bash
setup/run.sh day-05/cleanup.sh
```

`day-19/cleanup.sh --all` also deletes the `course` cluster, and `day-25/teardown.sh` deletes the `eks` cluster. `day-07/cleanup.sh --all` also removes the registry's data volume and its password files.

To remove everything the course created on the server, run the cleanups from day 25 back to day 2. Docker images are kept, so a re-run does not download them again; `docker image prune` frees that space. Leaving Docker Swarm (`docker swarm leave --force`) is left to you, because days 17 and 18 only leave it when nothing else uses it.

## License

The scripts, manifests and notes in this repository are released under the [MIT License](LICENSE). The course slides are not part of this repository and are not covered by it.

# How the pieces fit together

Two machines are involved. You edit files on one, and everything runs on the other.

```
 your computer ("the Mac")                     your Linux server
 ─────────────────────────                     ──────────────────────────────────────────────
  this repository                  ssh/rsync    ~/Projects/Kubernetes   (a copy of the repository)
  setup/run.sh day-NN/lab.sh  ───────────────▶  day-NN/lab.sh  ──▶  Docker Engine
  setup/validate.sh                                                     │
  a browser                  ◀──── HTTP(S) ────  published ports        ├─ plain containers   (days 1-16)
                                                 (8081, 8212, ...)      ├─ Docker Swarm       (days 17-18)
                                                                        ├─ kind cluster "course"  (days 19-23)
                                                                        │    one node = one container
                                                                        └─ kind cluster "eks"     (days 24-25)
                                                                             three nodes = three containers
```

## What runs where

| Part | Runs on | Notes |
|---|---|---|
| Editing, reading the READMEs | your computer | Nothing from the labs needs to run here. |
| `setup/sync.sh`, `run.sh`, `validate.sh`, `day-04/deploy.sh`, `day-05/check-from-mac.sh`, `day-18/from-mac.sh` | your computer | These use `ssh`, `scp` and `rsync` to reach the server. |
| Every `lab.sh`, `verify.sh`, `cleanup.sh` | the server | `setup/run.sh` copies the repository over first, then runs the script there. |
| Docker, Swarm, both `kind` clusters | the server | The Kubernetes "nodes" are Docker containers. |

## How a script is run

1. `setup/run.sh day-05/lab.sh` reads the server's SSH name from `setup/config.sh` (see `COURSE_HOST` in the README).
2. It copies the repository to `~/Projects/Kubernetes` on the server with `rsync`. This is one-way: nothing on the server is deleted.
3. It runs `bash day-05/lab.sh` there. The lab prints each command the way the slides show it, with the slide number in the step title, and runs it.
4. `setup/run.sh day-05/verify.sh` runs the checks. Each check prints `PASS` or `FAIL`, and the script ends with `N passed, M failed`.

## What each layer stands in for

```
 on AWS                                   here
 ──────                                   ────
  EC2 instance                             the server
  ECR registry                             registry:2 container                  (day 7)
  App Runner / ECS service                 container / Swarm service
  EKS cluster                              kind cluster
  load balancer                            Caddy, or MetalLB + an ingress controller
  EFS / EBS volumes                        shared volume / local-path volume
  Route 53 + public certificate            the server's Tailscale name + Caddy's own CA
```

The full table, with the limits of each stand-in, is in the [README](../README.md#what-replaces-aws).

## Shared helpers

| File | What it provides |
|---|---|
| `setup/lib.sh` | Used by every lab on the server: `step`, `run` (prints a command, then runs it), `check` / `summary`, `need_docker`, `need_k8s_tools`, `public_name` (the name a browser uses to reach the server). |
| `setup/config.sh` | Used by the scripts on your computer: reads `COURSE_HOST` and `COURSE_REMOTE_DIR` from the environment or from `setup/local.env`. |
| `setup/env.sh` | `source` it in your shell so the commands in the day READMEs (`ssh $COURSE_HOST ...`, `curl http://$SERVER:8888`) work as written. |
| `day-19/k8s-lib.sh` | Used by days 19-23: pins every `kubectl` and `helm` call to the `course` cluster and a namespace. |
| `day-24/env.sh` | Used by days 24-25: the `eks` cluster's name, its own kubeconfig file, and `load_image`. |

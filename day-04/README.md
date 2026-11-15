# Day 04: Getting files into containers

**Status:** run on the server on 2026-11-14; all 14 checks in `verify.sh` pass, and the deployed site loads from the Mac. Ready for you to validate.

**Slides:** 98-114

## What the slides cover

- Files written in a container live in its writable layer; the image stays read-only (slide 100).
- `docker cp`, into and out of a container, also while it is stopped (slide 102).
- Bind mounts: a host directory mapped into the container (slide 104).
- Two ways to write one: `--mount type=bind,...` and `-v host:container` (slides 105-106).
- Read-only bind mounts with `:ro` (slide 108).
- When to copy and when to bind-mount (slide 110).
- Deploying a website: `scp` to the server, then `docker cp` into the container (slides 112-114).

## What gets built here

| File | Runs on | What it does |
|---|---|---|
| `site/` | | A small static website: two pages and a stylesheet. |
| `lab.sh` | Server | Walks through `docker cp`, `-v`, `--mount` and `:ro`. Leaves two containers running. |
| `deploy.sh` | Mac | The two-step deployment from slides 112-114: `scp` to `~/app` on the server, then `docker cp` into the container. |
| `verify.sh` | Server | 14 pass/fail checks. |
| `cleanup.sh` | Server | Removes the containers, the scratch folder and `~/app`. |

The two containers show the two approaches side by side:

| Container | Port | How it gets its files | Slide 110 calls this |
|---|---|---|---|
| `day04-web` | 8081 | Copied in with `docker cp` | the production choice |
| `day04-bind` | 3000 | Bind mount of a folder on the server | the development choice |

## Run it

From the Mac:

```bash
setup/run.sh day-04/lab.sh
```

```bash
day-04/deploy.sh
```

```bash
setup/run.sh day-04/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 04` on the Mac | `14 passed, 0 failed` |
| 2 | Open http://<server>:8081 | A page headed "Served from a Docker container", styled, with a working link to "How this page got here" |
| 3 | Open http://<server>:8081/stopped.txt | `copied while the container was stopped` |
| 4 | Open http://<server>:3000 | The same site, but headed "Edited on the host, visible at once" |

Two things to try yourself, which show the difference between copying and mounting.

**Deployment needs an explicit copy.** Change the `<h1>` text in `day-04/site/index.html` on the Mac and reload port 8081: nothing changes. Then run this and reload: the new heading appears.

```bash
day-04/deploy.sh
```

**A bind mount needs nothing.** Change a file in the mounted folder on the server and reload port 3000: the change is there at once.

```bash
ssh $COURSE_HOST "echo 'hello from the host' > ~/Projects/Kubernetes/day-04/.work/dev-site/hello.txt"
```

Then open http://<server>:3000/hello.txt

## Differences from the slides

- The slides copy to `/home/ubuntu/app` on an EC2 server. Here the server is the machine you set up in `setup/local.env`, so the files go to `~/app` there.
- The slides bind-mount `$(pwd)` on the laptop where the files are edited. Docker runs on the server, so the bind mount points at a folder on the server (`day-04/.work/dev-site`, a copy of `site/` that the lab recreates on every run). A container can only bind-mount folders of the machine its daemon runs on.
- Folders that `-v` creates for a missing path belong to `root`, because the Docker daemon creates them. You can see this in step 7 of the lab.

## Without AWS

Nothing on this day needs AWS. The EC2 server in the deployment step is your own server.

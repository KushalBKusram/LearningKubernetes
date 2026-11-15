# Day 17: ECS part 1: tasks, clusters, services

**Status:** run on the server on 2026-11-14, twice; all 13 checks in `verify.sh` pass, and the page loads from the Mac. Validated.

**Slides:** 327-337

## What the slides cover

- Why ECS: more control than App Runner, multi-container services, mounted file systems (slide 328).
- The chapter's project, a PHP image upload form, and a second project, WordPress (slides 329-330).
- The three steps of an ECS deployment: task definition, cluster, service (slide 332).
- A task definition says what to run. It cannot be changed, only replaced by a new revision (slide 333).
- A task can hold several containers and is scaled as a whole (slide 334).
- A cluster is where tasks run; with Fargate, AWS manages the Docker hosts (slide 336).
- A service is a desired end state: it creates tasks, replaces crashed ones and moves to a new revision without an outage (slide 337).

## Without AWS

Docker Swarm stands in for ECS. Swarm mode is part of Docker Engine, so nothing is installed.

| ECS on the slides | Here |
|---|---|
| ECS cluster on Fargate | Single-node Docker Swarm on the server (`docker swarm init`) |
| Task definition | `stack.yaml` (Compose format) plus the image tag |
| New revision of a task definition | A new image tag, rolled out with `docker service update --image` |
| Task | A Swarm task (`docker service ps`) |
| Service with a desired count | A Swarm service with `replicas` |
| ECR image | A locally built image, `day17-app:v1` and `:v2` |

What this does not give you: the ECS console, Fargate sizing and pricing, IAM task roles, and security groups around the service.

## What gets built here

| File | What it does |
|---|---|
| `app/` | A small PHP page on the official `php:apache` image. It shows its image version and which task answered. |
| `stack.yaml` | The task definition and service: image, port 8500, health check, 2 replicas, one-at-a-time updates. |
| `lab.sh` | Builds v1 and v2, creates the cluster, deploys the service, kills a task, scales to 3, rolls out v2. |
| `verify.sh` | 13 pass/fail checks. |
| `cleanup.sh` | Removes the stack and images. Leaves swarm mode only if nothing else uses the cluster. |

## Run it

From the Mac:

```bash
setup/run.sh day-17/lab.sh
```

```bash
setup/run.sh day-17/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 17` on the Mac | `13 passed, 0 failed` |
| 2 | Open http://<server>:8500 and reload a few times | "Image version v2", and the task name changing between three values |
| 3 | Run `ssh $COURSE_HOST docker service ls` | `day17_web`, `replicated`, `3/3`, image `day17-app:v2` |
| 4 | Run `ssh $COURSE_HOST docker service ps day17_web` | Three running v2 tasks, with their stopped v1 predecessors listed under them, one of them `Failed` |

Two things to try yourself.

**The service repairs itself (slide 337).** Kill one of the three containers, then list the tasks again a few seconds later. There are three running tasks again, and one more `Failed` entry in the history.

```bash
ssh $COURSE_HOST 'docker kill $(docker ps -q --filter name=day17_web | head -1)'
```

```bash
ssh $COURSE_HOST docker service ps day17_web
```

**Go back to the previous revision.** Reload the page while this runs: it keeps answering, and ends up on v1. Run `setup/run.sh day-17/lab.sh` afterwards to return to the validated state.

```bash
ssh $COURSE_HOST docker service rollback day17_web
```

## Differences from the slides

- The slides deploy the official PHP image and get the application onto it later through EFS. Day 17 builds its own small PHP image instead, which slide 341 names as the better way, because a rolling update needs two versions of an image. Day 18 does it the slides' way.
- On ECS a task can hold several containers (slide 334). A Swarm task is always exactly one container. The course only uses single-container tasks, so nothing is lost in practice.
- A task definition revision is a numbered object in ECS. Swarm keeps only the current and the previous service definition, which is what `docker service rollback` uses.
- The published port 8500 is answered by Swarm's built-in routing, which already spreads requests over the tasks. On ECS that needs the load balancer from day 18.
- In the lab's rollout, 98 of 98 background requests were answered while the tasks were replaced.

## State on the server

- Swarm mode is now active on the server's Docker. Plain containers, Compose and kind are not affected by it.
- `day17_web` runs 3 tasks on port 8500, open on every network interface of the server.

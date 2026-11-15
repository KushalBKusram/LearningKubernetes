# Day 20: Pods in YAML, Deployments and labels

**Status:** run on the server on 2026-11-14 in the namespace `day20` of the day 19 cluster; the lab ran twice and all 14 checks in `verify.sh` pass. Ready for you to validate.

**Slides:** 385-403

## What the slides cover

- A pod written as YAML, applied with `kubectl apply -f`; `apiVersion`, `kind`, `metadata`, `spec`, `status` (slides 386-387).
- Workload types: ReplicaSet / Deployment, StatefulSet, DaemonSet, Job (slide 391).
- ReplicaSet versus Deployment (slides 393-394).
- WordPress as a Deployment with 3 replicas, created from the command line and from `deployment.yaml` (slides 395, 398).
- Reaching it with `kubectl port-forward`, for development only (slide 396).
- Labels, `-l app=wordpress,version=1.0`, and the immutable `spec.selector.matchLabels` (slides 400-402).
- Deployments are for stateless, interchangeable pods (slide 404).

StatefulSets (slide 405) and environment variables (slide 407) are on day 21.

## What gets built here

| File | What it does |
|---|---|
| `pod.yaml` | The smallest pod, with the five properties explained in comments. |
| `job.yaml`, `daemonset.yaml` | Two of the other workload types, to see them run. |
| `replicaset.yaml` | A ReplicaSet of 3 pods, to see what it does alone. |
| `deployment.yaml` | WordPress, 3 replicas, with labels. Stays running after the lab. |
| `lab.sh` | Walks through all of the above, then scaling, a rolling update and a rollback. |
| `verify.sh` | 14 pass/fail checks. |
| `cleanup.sh` | Deletes the namespace `day20`. |

WordPress runs here without a database, so it answers with an error page. The database comes on day 21 and the connection between them on day 22.

## Run it

From the Mac:

```bash
setup/run.sh day-20/lab.sh
```

```bash
setup/run.sh day-20/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 20` on the Mac | `14 passed, 0 failed` |
| 2 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course -n day20 get deployment,replicaset,pods'` | `wordpress-deployment` 3/3, **two** ReplicaSets (one with 3 pods, one with 0), and 3 pods named `wordpress-deployment-<hash>-<random>` |
| 3 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course -n day20 get deployments -l app=wordpress,version=1.1'` | The Deployment is found. `version=1.0` finds nothing, because the lab patched the label to 1.1 |
| 4 | In the lab output, step 7 | `field is immutable` when the selector is changed |

Things to try yourself (use `kubectl --context kind-course -n day20`, written as `K` below):

- **Self-healing.** `K delete pod <one of the three>`, then `K get pods`: a new pod with a different random name is already starting.
- **Scale.** `K scale deployment/wordpress-deployment --replicas=5` and watch `K get pods -w`.
- **Roll out and back.** `K set env deployment/wordpress-deployment APP_VERSION=3`, then `K rollout status ...` and `K get rs`: the old ReplicaSet stays at 0 pods. `K rollout undo deployment/wordpress-deployment` goes back.

## Differences from the slides

- **Reaching WordPress:** the slides keep a port-forward open and browse to port 8080. Here the lab opens one on port 8600 for a few seconds to show it works, then stops it. Nothing is left running. Browsing to WordPress from the Mac is possible on day 22 through a NodePort service.
- **HTTP from inside a pod:** the WordPress image has no `curl`, so the lab and the checks send the request with bash's `/dev/tcp`.
- **Rolling update:** the slides only describe it. The lab triggers one by adding an environment variable, which changes the pod template without downloading another image, then undoes it.
- **Image:** the node already holds `wordpress:latest` (copied from the server's Docker), and `deployment.yaml` sets `imagePullPolicy: IfNotPresent`, so nothing is downloaded from Docker Hub. For the tag `latest` the default would be `Always` (explained on day 21).
- **Resource requests** (`cpu: 25m`, `memory: 64Mi`) are added to every pod, so that several pods share this machine's memory sensibly. The slides leave them out.

## Without AWS

Nothing on this day needs AWS.

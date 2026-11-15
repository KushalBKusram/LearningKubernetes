# Day 19: Kubernetes, first cluster

**Status:** run on the server on 2026-11-14; all 17 checks in `verify.sh` pass, and the lab ran twice. Ready for you to validate.

**Slides:** 357-384

## What the slides cover

- What Kubernetes is and is not; the goal of the chapter (slides 358-360).
- Cluster overview: control plane, worker nodes, pods (slides 363, 365).
- A local cluster, `kubectl`, contexts, `get nodes`, `get pods -A` (slides 367-370).
- A first pod with `kubectl run`, restart policies `Always`, `Never`, `OnFailure` (slides 372-374).
- The control plane's components and the node's components (slides 377-379).
- How `kubectl` talks to the cluster (slide 380).
- Helm, the package manager (slide 382).
- The dashboard, a user and a login token (slide 384).

## What gets built here

| File | What it does |
|---|---|
| `kind-cluster.yaml` | The one-node cluster `course`, used by days 19-23. Publishes node ports 30080-30089 on the server. |
| `lab.sh` | Creates the cluster (if missing), then follows the slides step by step. |
| `headlamp-values.yaml` | Helm values for the dashboard. |
| `dashboard-token.sh` | Prints a one-hour login token for the dashboard. |
| `k8s-lib.sh` | Helpers shared by days 19-23: pins every `kubectl`/`helm` call to the `course` cluster and a namespace, and restarts cluster add-ons that crashed. |
| `verify.sh` | 17 pass/fail checks. |
| `cleanup.sh` | Removes the day 19 namespace. `--all` also deletes the cluster, which days 20-23 need. |

## Run it

From the Mac:

```bash
setup/run.sh day-19/lab.sh
```

```bash
setup/run.sh day-19/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 19` on the Mac | `17 passed, 0 failed` |
| 2 | Run `ssh $COURSE_HOST 'kind get clusters'` | One line: `course` |
| 3 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course get nodes'` | One node, `course-control-plane`, `Ready` |
| 4 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course get pods -n kube-system'` | `etcd`, `kube-apiserver`, `kube-scheduler`, `kube-controller-manager`, `kube-proxy`, `coredns` (two), all `Running` |
| 5 | Open http://<server>:30089 | The Headlamp login page asking for a token |
| 6 | Run `setup/run.sh day-19/dashboard-token.sh`, paste the output into that page | A cluster overview; choose the namespace `day19` |

Things to try yourself:

- **Restart policies.** The lab shows `Always` (the pod's finished container is started again) and `Never` (it stays `Completed`). Try the third one, which restarts only on errors: `kubectl run onfail --restart=OnFailure --image=ubuntu -- sh -c 'exit 1'`, then `kubectl get pod onfail -w`. The restart delay doubles each time (slide 373).
- **The API server is the only door.** `kubectl get nodes -v=6` prints the HTTPS request it sends. The dashboard page does the same through the API server with your token.

To use `kubectl` yourself, always name the cluster, because another cluster may share the kubeconfig: `kubectl --context kind-course ...`.

## Differences from the slides

- **Cluster:** the slides tick "Enable Kubernetes" in Docker Desktop. Here the cluster is [kind](https://kind.sigs.k8s.io/) on the server: the node is a Docker container named `course-control-plane`. It is one node that is both control plane and worker, like Docker Desktop's.
- **Dashboard:** the slides install the Kubernetes Dashboard. Its repository was archived in January 2026, so the lab uses Headlamp (a Kubernetes SIG project, Helm chart `headlamp/headlamp` 0.46.0). The flow is the same: install with Helm, create a user, make a token, log in.
- **Reaching the dashboard:** the slides use a proxy. Here the dashboard is a NodePort service on port 30089, which the cluster config publishes on the server. NodePort is explained on day 22.
- **The dashboard user** `dashboard-admin` has `cluster-admin` rights, so its token can do anything in the cluster. The dashboard is open on every network interface of the server, protected only by that token.
- **First pod:** the slides use `-it` and type `exit`. The lab's pod ends by itself after 5 seconds, so it can run unattended.
- **`kubectl` contexts:** the slides use `kubectl config use-context`. The labs pass `--context kind-course` on every call, so they can never touch another cluster on the same machine.
- **Control plane:** it runs as pods in `kube-system`. There is no cloud-controller-manager, because that exists only on a cloud provider's cluster.

## Known problem on this machine

The server allows each user only 128 inotify instances, shared by every container. While many containers start at once, `kube-proxy` and the storage provisioner can fail with `too many open files` and crash-loop. It happened once while creating the cluster and cleared after a restart of those pods, which `ensure_cluster_healthy` in `k8s-lib.sh` now does automatically. A second kind cluster does not fit. The permanent fix needs sudo:

```bash
echo 'fs.inotify.max_user_instances=512' | sudo tee /etc/sysctl.d/99-inotify.conf && sudo sysctl --system
```

## Without AWS

Nothing on this day needs AWS.

# Day 23: Kubernetes storage

**Status:** run on the server on 2026-11-14 in the namespace `day23` of the day 19 cluster; the lab ran twice and all 22 checks in `verify.sh` pass. Ready for you to validate.

**Slides:** 468-497

## What the slides cover

- Goal: WordPress installs and keeps its data, MariaDB stores real data (slide 469).
- Ephemeral volumes (live as long as the pod) versus persistent volumes (slide 472); Kubernetes volumes are not Docker volumes (slide 473).
- `emptyDir` (slide 475) and `hostPath` (slide 477).
- StorageClass, PersistentVolume (PV), PersistentVolumeClaim (PVC) (slides 479-487).
- A pod that uses a PVC (slide 489).
- `volumeClaimTemplates`: one PVC per pod of a StatefulSet (slide 491).
- Access modes, and why EFS and EBS differ (slides 493-494).

## What gets built here

| File | What it does |
|---|---|
| `emptydir-pod.yaml`, `hostpath-pod.yaml` | One pod per simple volume type. |
| `storageclass.yaml`, `pv.yaml`, `pvc.yaml`, `pvc-pod.yaml` | The chain StorageClass, PV, PVC, pod, made by hand. |
| `pvc-unmatched.yaml` | Two claims that cannot bind, and why (slide 486). |
| `rwx.yaml` | A ReadWriteMany claim on storage that cannot do it (slide 493). |
| `secret.yaml`, `mariadb.yaml` | MariaDB with `volumeClaimTemplates`. Stays running. |
| `wordpress.yaml` | WordPress with a shared volume, NodePort 30082. Stays running. |
| `lab.sh` | 11 steps in the order of the slides; it also installs WordPress. |
| `verify.sh` | 22 pass/fail checks. Some of them delete pods on purpose. |
| `cleanup.sh` | Deletes the namespace, the PV, the StorageClass and the node's data directories. |

## Run it

From the Mac:

```bash
setup/run.sh day-23/lab.sh
```

```bash
setup/run.sh day-23/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 23` on the Mac | `22 passed, 0 failed` |
| 2 | Open http://<server>:30082 | A WordPress site titled "Day 23 WordPress", **not** the installer: it is already installed |
| 3 | Open http://<server>:30082/wp-login.php and log in as `admin`, with the password from `day-23/secret.yaml` (decoded from Base64) | The WordPress dashboard |
| 4 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course -n day23 get pvc'` | `local-pvc`, `mariadb-data-mariadb-statefulset-0` and `wordpress-data`, all `Bound` |
| 5 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course get pv'` | `day23-local-pv` `Bound` to `day23/local-pvc`, plus the two volumes that the cluster created for the other claims |

Things to try yourself (`K` is `kubectl --context kind-course -n day23`):

- **The proof that storage works.** Change something in WordPress (write a post), then `K delete pod --all`. When the pods are back, the post is still there. On day 21 the same experiment lost everything.
- **Where the data is.** The node is a Docker container: `ssh $COURSE_HOST docker exec course-control-plane ls /opt/local-path-provisioner` lists one directory per dynamically created claim, and `ls /mnt/day23-pv` shows the hand-made volume.
- **A claim waits for a pod.** `K get pvc local-pvc` before and after a pod uses it: `Pending`, then `Bound`.

## Differences from the slides

- **StorageClass `hostpath`:** the slides use the class that Docker Desktop ships with. kind has a different default class, `standard` (a local-path provisioner, `rancher.io/local-path`). The lab uses `standard` for claims that Kubernetes should fulfil by itself, and creates a class called `hostpath` for the hand-made PV/PVC chain, so the YAML matches the slides.
- **Storage is local, in the node:** all of these volumes are directories inside the Docker container that is the node, on the server's disk. That is what hostPath volumes always are. On AWS the same YAML would use EBS (one node at a time) or EFS (many nodes), see day 25.
- **WordPress shares one claim between two replicas:** that works because the claim is `ReadWriteOnce` and this cluster has a single node (`ReadWriteOnce` means one *node*, not one pod). On several nodes it would need `ReadWriteMany`, which this storage cannot do: the lab shows the refusal (step 9).
- **The first WordPress pod starts alone,** and the lab adds the second one afterwards. Two pods starting at once on an empty volume would both try to copy WordPress's files into it.
- **WordPress is installed by the lab** with the same form the browser would send (`curl`), so that the result can be checked. The admin login is `admin` and the password from `secret.yaml`: the slides' demo value for a throwaway local cluster.
- **Capacity numbers are labels here:** a hostPath volume has no size limit. The `1Gi` is only used to match a claim to a volume.
- **PV reclaim policy `Retain`:** the data in `/mnt/day23-pv` stays when the claim is deleted, and the PV then shows `Released`.

## Without AWS

Nothing on this day needs AWS. EFS and EBS (slides 470, 494) are discussed, not used: EFS maps to `ReadWriteMany` shared storage, EBS to `ReadWriteOnce` block storage that is tied to one node (and one availability zone). Day 25 imitates both.

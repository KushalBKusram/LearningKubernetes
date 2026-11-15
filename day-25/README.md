# Day 25: EKS part 2: storage, availability zones, teardown

**Status:** run on the server on 2026-11-14 on the day 24 cluster; all 17 checks in `verify.sh` pass. `teardown.sh` was tested, and the cluster was then rebuilt with the day 24 and day 25 labs. Ready for you to validate. (Written to a first draft earlier that day as blocked by the inotify limits; those limits have since been raised.)

**Slides:** 534-550

## What the slides cover

- Two kinds of storage on EKS: EFS (shared filesystem) and EBS (block storage) (slide 535).
- EFS: create the volume, open it to the nodes, add the driver, then a PersistentVolume and claim for WordPress (537).
- EBS: usable by one node at a time, which is `ReadWriteOnce` (539).
- Kubernetes suits stateless apps; a managed database is the better choice, but here the database runs in the cluster to see how stateful apps work (540).
- An EBS volume only works in its own availability zone. Automatic provisioning can put it in the wrong one (542-543). The easy fix is to run the cluster in one zone (544-545); the harder fix is a node group per zone (546).
- Deleting the cluster, and then everything `eksctl` leaves behind (550).

## What gets built here

| File | What it does |
|---|---|
| `mysql.yaml` | MySQL as a StatefulSet in zone `eu-west-3a`, with a `ReadWriteOnce` volume from the default `standard` class. |
| `wordpress.yaml` | WordPress, 2 pods spread across both zones, with `wp-content` on a `ReadWriteMany` volume from the `efs` class. NodePort 30081, published as port 8450. |
| `zone-demo.yaml` | A pod that claims the database volume but must run in the other zone. It stays `Pending`. |
| `lab.sh` | Installs the `efs` class, deploys MySQL and WordPress, and shows each of the points above. |
| `verify.sh` | 17 pass/fail checks. |
| `teardown.sh` | Deletes the cluster in the order of slide 550 and the leftovers outside it. |

## Run it

The day 24 cluster has to exist first. From the Mac:

```bash
setup/run.sh day-25/lab.sh
```

```bash
setup/run.sh day-25/verify.sh
```

When you are finished with the cluster:

```bash
setup/run.sh day-25/teardown.sh
```

After a teardown, `setup/run.sh day-24/lab.sh` and then `setup/run.sh day-25/lab.sh` build everything again.

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 25` on the Mac | `17 passed, 0 failed` |
| 2 | Open http://<server>:8450 | WordPress' installation screen ("Select a default language" or the site form). No account is created by the lab |
| 3 | Run `ssh $COURSE_HOST 'kubectl --context kind-eks --kubeconfig ~/.kube/eks.config get pods -o wide'` | Two `wordpress-...` pods on different nodes and `mysql-0` on `eks-worker` |
| 4 | Run `ssh $COURSE_HOST 'kubectl --context kind-eks --kubeconfig ~/.kube/eks.config get pvc'` | `wp-content` `RWX` class `efs`, and `data-mysql-0` `RWO` class `standard`, both `Bound` |
| 5 | Run `ssh $COURSE_HOST 'kubectl --context kind-eks --kubeconfig ~/.kube/eks.config describe pod zone-demo'` after `kubectl apply -f ~/Projects/Kubernetes/day-25/zone-demo.yaml` | The pod `Pending`, with an event saying a node "didn't match PersistentVolume's node affinity" |

Two things to try yourself.

**Shared files.** Write a file in one WordPress pod and read it from the other. They run in different zones:

```bash
ssh $COURSE_HOST 'export KUBECONFIG=~/.kube/eks.config; K="kubectl --context kind-eks"; P=$($K get pods -l app=wordpress -o name); A=$(echo "$P" | sed -n 1p); B=$(echo "$P" | sed -n 2p); $K exec $A -- sh -c "echo hello > /var/www/html/wp-content/hi.txt"; $K exec $B -- cat /var/www/html/wp-content/hi.txt'
```

**Delete the database pod.** The StatefulSet recreates it on the same node, and the data written before is still there. `lab.sh` step 6 does this with a table row; to see it by hand:

```bash
ssh $COURSE_HOST 'export KUBECONFIG=~/.kube/eks.config; kubectl --context kind-eks delete pod mysql-0 && kubectl --context kind-eks rollout status statefulset/mysql'
```

## Differences from the slides

- **EBS is not zone-aware here.** The `standard` class (local-path) ties a volume to a node (`kubernetes.io/hostname`), not to a zone. The effect for the pod is the same as the slides describe for EBS: it can only run where the volume is, and a pod forced into the other zone stays `Pending`. The scheduler message names node affinity, not a zone.
- **EFS is an NFS server inside the cluster.** The Helm chart `nfs-server-provisioner` stores its data on a `standard` volume, so the "filesystem" lives on one node's disk. It behaves like EFS for the pods (`ReadWriteMany` across zones) but is not highly available.
- **No manual volume setup.** On AWS you create the EFS and EBS volumes yourself and add IAM roles for the drivers (slides 537, 548). Here the provisioner creates volumes when a claim asks for one, so there is no PersistentVolume to write by hand. Day 23 covers PVs and claims in detail.
- **MySQL is pinned to a zone with `nodeSelector`,** which is slide 544's easy answer. The slides do it by configuring the node group's autoscaling group to one zone. The harder answer (slide 546) is not built.
- **WordPress shares `wp-content` only.** The core files stay in each pod's own image layer, as in a normal container.
- **No managed database.** Slide 540 recommends one for real use; here MySQL runs in the cluster, as the slide itself does for the exercise.

## Without AWS

| On the slides | Here |
|---|---|
| EFS volume, EFS driver, IAM role | `nfs-server-provisioner` Helm chart, StorageClass `efs` (`ReadWriteMany`) |
| EBS volume, EBS driver, IAM role | The default `standard` class (local-path), `ReadWriteOnce`, bound to one node |
| Availability zones `eu-west-3a/b/c` | The labels `topology.kubernetes.io/zone` on the kind nodes |
| `eksctl delete cluster`, then removing volumes, load balancers, NAT gateway, elastic IPs, security groups, the VPC | `teardown.sh`: delete volumes and load balancers, `kind delete cluster`, then the leftover container, image and kubeconfig |

What this cannot teach: EFS and EBS performance and billing, the CSI drivers and their IAM roles, and the long list of AWS resources that survive `eksctl delete cluster` (slide 550).

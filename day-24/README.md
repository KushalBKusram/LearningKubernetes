# Day 24: EKS part 1: cluster, load balancers, Ingress, HTTPS

**Status:** run on the server on 2026-11-14; all 20 checks in `verify.sh` pass. Ready for you to validate. (Written to a first draft earlier that day as blocked by the inotify limits; those limits have since been raised and the day was built.)

**Slides:** 498-533

## What the slides cover

- EKS costs, and creating a cluster with `eksctl` (slides 500-506).
- nginx behind a NodePort Service, blocked by the nodes' security group until a port is opened (508-509).
- A LoadBalancer Service, which builds an EC2 load balancer on AWS (511-513).
- An application load balancer created by hand, and why that is fragile (516-518).
- Ingress and the AWS Load Balancer Controller (519-523), HTTPS with a certificate from Certificate Manager (525).
- Sending traffic straight to pods with `target-type: ip` and the VPC CNI (527-531).
- Using your own image from ECR (533).

## What gets built here

| File | What it does |
|---|---|
| `cluster.yaml` | The cluster definition: 1 control plane and 2 workers, in zones `eu-west-3a` and `eu-west-3b`, with ports published on the server. |
| `env.sh` | Settings shared with day 25: the cluster name, its own kubeconfig, and `load_image`. |
| `nginx.yaml` | nginx Deployment (2 pods, one per node) and three Services: NodePort 30080, LoadBalancer, and a plain one for the Ingress. |
| `hello.yaml`, `image/` | A custom image, `day24-hello:1`, built on the server and copied into the nodes. |
| `ingress.yaml` | The Ingress, with TLS, for `nginx.eks.local` and `hello.eks.local`. |
| `lab.sh` | Creates the cluster and walks through all eight steps. |
| `verify.sh` | 20 pass/fail checks. |
| `cleanup.sh` | Removes what day 24 added. `--cluster` also deletes the cluster (day 25's `teardown.sh` does the full job). |

The cluster is named `eks` and has its own kubeconfig file, `~/.kube/eks.config`, so it never touches `~/.kube/config`. Always use `--context kind-eks` with `kubectl` and `helm`.

## Run it

From the Mac:

```bash
setup/run.sh day-24/lab.sh
```

```bash
setup/run.sh day-24/verify.sh
```

The first run takes a few minutes: it creates the cluster and pulls the ingress controller.

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 24` on the Mac | `20 passed, 0 failed` |
| 2 | Open http://<server>:8430 and reload a few times | `nginx pod nginx-... on node eks-worker` or `eks-worker2`, changing between reloads |
| 3 | Open http://<server>:8431 | The same, through node #2's port |
| 4 | Open http://<server>:8440 | The same, through the load balancer made by hand |
| 5 | Run `curl -k --resolve hello.eks.local:8443:$(dig +short $SERVER) https://hello.eks.local:8443` on the Mac | `hello from the custom image day24-hello:1` |
| 6 | Run `curl -sI -H 'Host: nginx.eks.local' http://$SERVER:8480` | `301 Moved Permanently`, pointing at HTTPS |
| 7 | Run `ssh $COURSE_HOST 'kubectl --context kind-eks --kubeconfig ~/.kube/eks.config get nodes -L topology.kubernetes.io/zone'` | 3 nodes `Ready`, the workers in `eu-west-3a` and `eu-west-3b` |

Why the hostnames: an Ingress routes by `Host`, so a browser needs `nginx.eks.local` to resolve to the server. `--resolve` does that for one `curl` call. To use a browser, add `<the server's IP address>  nginx.eks.local hello.eks.local` to `/etc/hosts` on the Mac (this needs your sudo password, so it is left to you) and open https://nginx.eks.local:8443. The browser will warn about the self-signed certificate.

Two things to try yourself.

**The load balancer address is not reachable from the Mac.** On the server, the LoadBalancer Service has an address from MetalLB:

```bash
ssh $COURSE_HOST 'kubectl --context kind-eks --kubeconfig ~/.kube/eks.config get service nginx-lb'
```

`curl` that `EXTERNAL-IP` from the server and it answers. From the Mac it does not: the address exists only on the server's Docker network. That is why the Mac-facing ports (8430, 8431, 8440, 8443, 8480) are published host ports instead.

**The ingress controller talks to pods, not Services.** This prints the controller's nginx upstreams, which are the pod addresses:

```bash
ssh $COURSE_HOST 'kubectl --context kind-eks --kubeconfig ~/.kube/eks.config -n nginx-ingress exec deploy/nginx-ingress-controller -- sh -c "grep -h \"server 10\" /etc/nginx/conf.d/*.conf"'
```

Compare them with `kubectl get pods -o wide`.

## Differences from the slides

- **Ingress controller.** The slides name the community `ingress-nginx` as the common choice outside AWS. That project was retired and its repository archived in March 2026, so the maintained F5 NGINX Ingress Controller (chart 2.8.1, app 5.7.1) is used.
- **No Mac-reachable load balancer.** On AWS the load balancer has a public address. MetalLB's address here is reachable from the server only (see above).
- **HTTP redirects.** The F5 controller sends plain HTTP to HTTPS (301) by default once an Ingress has TLS. The slide 525 annotations make the ALB listen on both ports instead.
- **`externalTrafficPolicy: Cluster`.** The chart defaults to `Local`, under which only the node that runs the controller pod answers on the NodePort. The published port sits on the control-plane node, which has no controller pod, so the lab sets `Cluster`. On AWS the load balancer's health checks pick the right node and this does not come up.
- **`target-type: ip` and the VPC CNI.** Not needed. kind pods already have addresses that the controller can reach, and the F5 controller always sends to pod addresses. The lab shows this in step 8; it does not reproduce the AWS CNI add-on.
- **Image loading.** `kind load docker-image` fails here (`content digest ... not found`), because Docker keeps multi-platform images and kind tries to import platforms that were never pulled. `env.sh` uses `docker save --platform` and `kind load image-archive` instead.
- **Cluster creation.** `eksctl` takes 15 to 30 minutes (slide 506); `kind` takes about a minute.

## Without AWS

| On the slides | Here |
|---|---|
| `eksctl create cluster` | `kind create cluster --config cluster.yaml` |
| Nodes' public IPs and an opened security-group port | `extraPortMappings` in `cluster.yaml` |
| EC2 load balancer for a LoadBalancer Service | MetalLB, address pool `<docker network>.255.200-220` |
| Application load balancer made by hand | An nginx container, `day24-manual-lb`, in front of both nodes |
| AWS Load Balancer Controller | F5 NGINX Ingress Controller |
| Certificate Manager certificate (ARN annotation) | Self-signed certificate in the Secret `nginx-eks-tls` |
| ECR | `docker save` and `kind load image-archive` |

What this cannot teach: real security groups and VPC routing, how long an ALB takes to provision, ACM certificate validation, and what the cluster costs.

# Day 22: Kubernetes networking, Services

**Status:** run on the server on 2026-11-14 in the namespace `day22` of the day 19 cluster. the lab ran twice and all 21 checks in `verify.sh` pass. Ready for you to validate.

**Slides:** 442-467

## What the slides cover

- Every pod has its own IP address; any pod can reach any other (slide 445).
- IP addresses change, so they are a poor way to find a pod. Services give a stable address (slides 448-449).
- Automatic failover: pods behind a Service come and go, the Service's address stays (slides 450-452).
- `kubectl expose`, and Services in YAML with a `selector` (slide 454).
- Several objects in one YAML file, separated by `---` (slide 456).
- DNS: Services are reachable by name through CoreDNS (slide 458).
- Service types: `ClusterIP`, `LoadBalancer`, `NodePort` (slide 460).
- A NodePort Service for WordPress on port 30080, and the three ports `port`, `targetPort`, `nodePort` (slides 462-465).
- Named ports (slide 467).

## What gets built here

| File | What it does |
|---|---|
| `secret.yaml` | The database credentials, as on day 21. |
| `mariadb.yaml` | MariaDB (StatefulSet) and its ClusterIP Service `mariadb-service`, in one file. |
| `wordpress.yaml` | WordPress (3 replicas) and two NodePort Services, in one file: `wordpress-service` on 30080, and `wordpress-ports` on 30081 with three different port numbers. |
| `lab.sh` | The 12 steps in the order of the slides. |
| `verify.sh` | 21 pass/fail checks. |
| `cleanup.sh` | Deletes the namespace `day22`, which frees the node ports 30080 and 30081. |

WordPress now reaches the database by the name `mariadb-service`, and shows its installer page. There is still no storage, so nothing it installs survives a pod restart: that is day 23.

## Run it

From the Mac:

```bash
setup/run.sh day-22/lab.sh
```

```bash
setup/run.sh day-22/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 22` on the Mac | `21 passed, 0 failed` |
| 2 | Open http://<server>:30080 | WordPress's installation page ("Welcome", language or site-title form). This proves the chain works: browser, node port, Service, pod, and the database through `mariadb-service` |
| 3 | Open http://<server>:30081 | The same page, through the second Service |
| 4 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course -n day22 get services,endpointslices'` | `mariadb-service` (ClusterIP, 3306), `wordpress-service` (`80:30080/TCP`), `wordpress-ports` (`8080:30081/TCP`), and endpoint lists with the pods' IPs |
| 5 | In the lab output, step 2 | The old database IP is unreachable after the pod is replaced; the Service address in step 4 is unchanged |
| 6 | In the lab output, step 8 | The LoadBalancer Service stays `<pending>` |

Things to try yourself (`K` is `kubectl --context kind-course -n day22`):

- **Failover in a browser.** Reload http://<server>:30080 repeatedly while you run `K delete pod <a wordpress pod>`: the page keeps loading.
- **See the endpoints change.** `K get endpointslices -l kubernetes.io/service-name=wordpress-service -w`, then delete a pod in another terminal: the address list changes while the Service keeps its address.
- **Look up a name.** `K exec <wordpress pod> -- getent hosts wordpress-service` prints the Service's cluster IP.

## Differences from the slides

- **Reaching WordPress:** the slides use a NodePort on Docker Desktop, where it is simply `localhost:30080`. The cluster here runs in a Docker container on the server, so day 19's cluster config publishes node ports 30080-30089 on the server, and the Mac uses the server's name.
- **`nslookup`:** the slides install `dnsutils` into a pod. The WordPress image already has `getent`, which asks the same cluster resolver, so nothing is installed.
- **Connection tests** use bash's `/dev/tcp`, because the images have neither `ping`, `nc` nor `curl`.
- **MariaDB readiness:** the StatefulSet has a readiness probe, so the Service only sends traffic to the database once it accepts connections (the first start takes several seconds). The slides leave probes out.
- **Names that appear twice:** `wordpress-service` and `mariadb-service` also exist in day 21's and day 23's namespaces. Namespaces keep them apart; only the node ports (30080, 30081 here, 30082 on day 23) are shared by the whole cluster.
- **Failover test:** the slides draw it. The lab sends 30 requests while it deletes a pod, and counts the answers.

## Without AWS

Nothing on this day needs AWS. The `LoadBalancer` type needs a cloud provider: on AWS it creates a real load balancer (day 24). Here the lab only shows it staying `<pending>`.

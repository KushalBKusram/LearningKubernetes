# Day 21: StatefulSets, configuration and Secrets

**Status:** run on the server on 2026-11-14 in the namespace `day21` of the day 19 cluster; the lab ran twice and all 16 checks in `verify.sh` pass. Ready for you to validate.

**Slides:** 404-414. Slides 416-441 repeat this section, so it is covered once.

## What the slides cover

- Deployment (stateless, interchangeable pods, random names) versus StatefulSet (sticky identity, ordered start, reverse-ordered stop) (slides 404-405).
- MariaDB does not start without a password; environment variables fix that (slide 407).
- Secrets: Base64-encoded objects that keep credentials out of the configuration; `secretKeyRef` (slides 409-410).
- Using your own images: they must be on every node, or in a private registry (slide 413).
- `imagePullPolicy`: `IfNotPresent`, `Never`, `Always`, and the default rules (slide 414).

## What gets built here

| File | What it does |
|---|---|
| `statefulset-ordered.yaml` | Three small pods to show sticky names and ordering. |
| `statefulset-no-password.yaml` | MariaDB with no configuration: it crashes, and the log says why. |
| `statefulset-env.yaml` | MariaDB with the password as a plain environment variable. |
| `secret.yaml`, `statefulset.yaml` | The Secret, and MariaDB reading its credentials from it. Stays running. |
| `app/` | A tiny Python web app and its `Dockerfile`: the "own image". |
| `app-deployment.yaml` | The app as a Deployment, using a variable and the Secret. Stays running. |
| `pull-policy.yaml` | The same image under `IfNotPresent`, `Never` and `Always`, plus a missing image with `Never`. |
| `lab.sh` | Runs through the steps in order. |
| `verify.sh` | 16 pass/fail checks. |
| `cleanup.sh` | Deletes the namespace and the `day21-app:1.0` image. |

## Run it

From the Mac:

```bash
setup/run.sh day-21/lab.sh
```

```bash
setup/run.sh day-21/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 21` on the Mac | `16 passed, 0 failed` |
| 2 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course -n day21 get pods'` | `mariadb-statefulset-0` and two `day21-app-<hash>-<random>` pods, all `Running` |
| 3 | In the lab output, step 1 | `ordered-0`, `ordered-1`, `ordered-2`, created about 12 seconds apart; after scaling to 1 only `ordered-0` is left |
| 4 | In the lab output, step 2 | `Database is uninitialized and password option is not specified` |
| 5 | In the lab output, step 7 | `pull-ifnotpresent` and `pull-never` Running; `pull-always` `ErrImagePull`; `pull-never-missing` `ErrImageNeverPull` |
| 6 | Run `ssh $COURSE_HOST '~/.local/bin/kubectl --context kind-course -n day21 get secret my-mariadb-secret -o jsonpath="{.data.password}" \| base64 -d'` | `secretpassword`: the Secret is encoded, not encrypted |

Things to try yourself (`K` is `kubectl --context kind-course -n day21`):

- **Names.** `K delete pod mariadb-statefulset-0`, then `K get pods`: the replacement has the same name. Do the same with a `day21-app` pod: its replacement gets a new random name.
- **The app's view.** `K exec deploy/day21-app -- python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000').read().decode())"` shows the greeting, the user, and the password's length (14), but never the password.
- **Change the Secret.** Edit `secret.yaml`, apply it, and look at the app again: nothing changes, because environment variables are read when a container starts. `K rollout restart deployment/day21-app` picks up the new value.

## Differences from the slides

- **Your own image (slide 413):** the slides rely on Docker Desktop sharing its images with its Kubernetes. A kind node has its own image store, so the lab copies the image in with `kind load docker-image`. The shared helper `preload_image` (in `day-19/k8s-lib.sh`) imports base images a different way, because `kind load` fails on images that Docker stores for several platforms.
- **The StatefulSet's Service:** `statefulset.yaml` names `serviceName: mariadb-service`, which does not exist until day 22. A StatefulSet runs fine without it. It only matters for the pods' DNS names.
- **MariaDB, not MySQL:** the slides use MariaDB (the plan called it MySQL).
- **`imagePullPolicy` on `mariadb:latest`:** set to `IfNotPresent` explicitly. With `:latest` Kubernetes defaults to `Always`, which would download the image on every pod start (slide 414).
- **No storage yet:** the lab shows that a replaced database pod comes back empty. Day 23 fixes that with a PersistentVolumeClaim.
- **The credentials** in `secret.yaml` are the slides' own example (`admin` / `secretpassword`): a demo for a throwaway local cluster. Base64 in a file in git is not a way to protect real secrets (slide 411 points at AWS Secrets Manager for that).

## Without AWS

Nothing on this day needs AWS. On AWS the image would come from ECR, and secrets could come from AWS Secrets Manager (slides 411, 413); here the image is copied into the node and the Secret is a Kubernetes object.

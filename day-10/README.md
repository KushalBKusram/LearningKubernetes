# Day 10: Smaller, safer images

**Status:** run on the server on 2026-11-14; all 32 checks in `verify.sh` pass, and the app answers from the Mac. Ready for you to validate.

**Slides:** 216-231. It needs the app sources from day 6.

## What the slides cover

- Why smaller images deploy and update faster (slide 217).
- Alpine Linux: a base of a few megabytes, using the musl C library instead of glibc (slides 219-221).
- Problem 1: programs are tuned for glibc, and musl behaves differently in places (slide 222).
- Problem 2: binaries must be built for musl; packages from non-distribution package managers such as `pip` often only ship glibc builds, so Alpine has to compile them (slides 223-224).
- Multi-stage builds: compile in one image, run in a small one. Several `FROM` lines, `COPY --from=`, named stages with `AS` (slides 226-228).
- `HEALTHCHECK`, with the statuses starting, healthy and unhealthy (slide 230).

## What gets built here

| Path | What it is |
|---|---|
| `variants/Dockerfile` | The day 6 Dockerfile with the base image as a build argument. |
| `ts-app/` | A TypeScript version of the app. It has to be compiled with `tsc`, which is the large build step. `Dockerfile.single` builds it in one stage, `Dockerfile` in two stages and adds a `HEALTHCHECK`. |
| `lab.sh` | Builds everything, compares sizes, shows the musl/glibc problems, and plays with the health status. Leaves `day10-app` running. |
| `verify.sh` | 32 pass/fail checks. |
| `cleanup.sh` | Removes the container, images and scratch folder. Keeps the pulled base images. |

Measured on this machine (decimal units, as `docker image ls` shows them):

| Image | Size |
|---|---|
| `day10-app:debian` (`node:26`) | 1.8 GB |
| `day10-app:slim` (`node:26-slim`) | 364 MB |
| `day10-app:alpine` (`node:26-alpine`) | 263 MB |
| `day10-ts:single` (compiler left in) | 1.8 GB |
| `day10-ts:multistage` | 263 MB |

The multi-stage image is as small as the Alpine one: it contains the Alpine base, the production dependencies and the compiled code, and nothing from the build stage.

The app runs on port 8110.

The first run pulls three base images (`node:26-slim`, `node:26-alpine`, `python:alpine`).

## Run it

From the Mac:

```bash
setup/run.sh day-10/lab.sh
```

```bash
setup/run.sh day-10/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 10` on the Mac | `32 passed, 0 failed` |
| 2 | Open http://<server>:8110/api/info | JSON with the greeting "Hello from the TypeScript app" |
| 3 | Run `ssh $COURSE_HOST "docker image ls 'day10*'"` | The five images above, with about the sizes in the table (see the `DISK USAGE` column) |
| 4 | Run `ssh $COURSE_HOST "docker ps --filter name=day10-app --format '{{.Names}} {{.Status}}'"` | `day10-app Up ... (healthy)` |
| 5 | Run `ssh $COURSE_HOST "docker run --rm day10-ts:multistage ls /app"` | `dist`, `node_modules`, `package.json`, `package-lock.json`. No `src`, and no TypeScript in `node_modules` |

Things to try yourself.

**Watch the health status change.** Break the app on purpose, wait about ten seconds, and look at `docker ps`. Then repair it:

```bash
ssh $COURSE_HOST "docker exec day10-app touch /tmp/unhealthy"
```

```bash
ssh $COURSE_HOST "sleep 10; docker ps --filter name=day10-app --format '{{.Names}} {{.Status}}'"
```

```bash
ssh $COURSE_HOST "docker exec day10-app rm /tmp/unhealthy"
```

The status goes from `(healthy)` to `(unhealthy)` and back. Note that Docker does not restart the container: the status is only recorded.

**See the glibc problem yourself.** Alpine has no glibc, so a program built for glibc will not start:

```bash
ssh $COURSE_HOST "docker run --rm node:26-alpine ls -l /lib64/ld-linux-x86-64.so.2"
```

The file does not exist. On `node:26-slim` it does. That loader is exactly what the failing program from the lab was looking for.

## Differences from the slides

- **The multi-stage example is a TypeScript Node.js app, not the slides' React app.** The slides build a React app with Node.js and serve the result with nginx on Alpine (day 12 covers React). A TypeScript app has the same shape: a compiler is needed to build and not to run. The multi-stage idea is the same, with a Node.js runtime in place of nginx.
- **The HEALTHCHECK uses Node.js, not `curl`.** The slide's example is `curl -f http://localhost`. `node:alpine` has no `curl`, and installing it would add to the image, so the check makes the request with Node's own `fetch`.
- **A shorter health interval.** The slide shows the defaults (30 s). The lab uses 3 s so the status change can be watched in a few seconds.
- **The pip example shows which wheels `pip` accepts**, not an actual install of scikit-learn, which would compile for many minutes on Alpine. The accepted-tags list shows the cause: Debian slim accepts only `manylinux` (glibc) wheels, Alpine only `musllinux` ones.
- **The multi-stage image also runs as a non-root user** (`USER node`). That is not on the slides; it is a one-line safety improvement.

## Without AWS

Nothing on this day needs AWS.

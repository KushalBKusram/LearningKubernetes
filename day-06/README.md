# Day 06: App Runner and Dockerfiles

**Status:** run on the server on 2026-11-14; all 21 checks in `verify.sh` pass, and the app answers from the Mac. Ready for you to validate.

**Slides:** 133-157

## What the slides cover

- Managed services versus running your own server, and AWS App Runner for stateless containers (slides 136-138).
- A Dockerfile turns into an image with `docker build`, and the whole build context is sent to the daemon (slides 142-143).
- `COPY` and `ADD` (slide 145), `CMD` (147), `ENTRYPOINT` (149), `EXPOSE` (151), `.dockerignore` (153), `RUN` (155), `WORKDIR` (157).
- The slides build a custom Node.js app image and later publish it to a registry (days 7 and 9).

## What gets built here

| Path | What it is |
|---|---|
| `app/` | A small Node.js web app (Express) with its `Dockerfile` and `.dockerignore`. It is stateless and shows its version, container name and platform. |
| `demos/` | Three tiny Dockerfiles for `CMD`, `ENTRYPOINT` and `COPY` versus `ADD`. |
| `lab.sh` | Builds the image, shows the cache, runs the app, then walks through each instruction. Leaves `day06-app` running on port 8101. |
| `verify.sh` | 21 pass/fail checks. |
| `cleanup.sh` | Removes the containers, demo images and scratch folder. Keeps the `day06-app` image. |
| `build-steps.sh` | Helper that prints one line per build step instead of BuildKit's full log. |

The app has three endpoints: `/` (a page), `/api/info` (JSON) and `/health`.

Days 7, 9 and 10 reuse this app and its image.

## Run it

From the Mac:

```bash
setup/run.sh day-06/lab.sh
```

```bash
setup/run.sh day-06/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 06` on the Mac | `21 passed, 0 failed` |
| 2 | Open http://<server>:8101 | A page headed "Hello from the Node app", with version 1.0.0, a container name and `linux/x64` |
| 3 | Open http://<server>:8101/api/info | The same values as JSON |
| 4 | Run `ssh $COURSE_HOST "docker run --rm day06-app ls -a /app"` | `node_modules`, `package.json`, `package-lock.json`, `server.js`. No `NOTES.md` and no `Dockerfile`, because `.dockerignore` excludes them |

Things to try yourself.

**The container is replaceable (slide 138).** Note the container name on the page, replace the container, and reload: the name changes, the content does not.

```bash
ssh $COURSE_HOST "docker rm -f day06-app && docker run -d --name day06-app -p 8101:3000 --restart unless-stopped day06-app"
```

**The build cache.** Rebuild twice and watch which steps are marked cached. Then change one line of `app/server.js`, sync, and rebuild: only the last `COPY` step runs again, and `npm ci` stays cached because `package.json` did not change. That is why the Dockerfile copies the dependency list before the rest.

```bash
setup/run.sh day-06/lab.sh
```

## Differences from the slides

- The slides use a Node app from the course material. This one is written for the lab and is small (one file).
- The slides run `docker build` in the folder with the app. The build here runs on the server, so the app folder is copied there first by `setup/run.sh`. The build context is sent to the server's daemon either way (slide 142).
- `npm ci` needs `package-lock.json`. It was generated once inside a `node` container, because Node is not installed on the Mac or the server.

## Without AWS

App Runner is not available. It runs a stateless container, gives it HTTPS and a domain, and scales it. Here the same container runs on the server:

- The container is stateless, which is the property App Runner requires, and it is replaceable at any time.
- HTTPS and the domain would come from Caddy (day 5), placed in front of the container.
- Scaling to several copies is shown on day 16, with Caddy balancing between instances.

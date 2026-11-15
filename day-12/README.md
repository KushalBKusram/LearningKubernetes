# Day 12: Full-stack deployment (optional chapter)

**Status:** run several times on the server on 2026-11-14; all 18 checks in `verify.sh` pass (see the note at the end of this section about one failed run). The React page was also loaded and used in a scripted browser (jsdom) against the running stack. I could not open it in the app's built-in browser pane, because that pane blocked the page's script; it has not been looked at in a real browser. Ready for you to validate.

**Slides:** 248-264. The slides call this chapter optional: it teaches deployment, not new Docker.

## What the slides cover

- A full-stack app: a React frontend, a Node.js backend and MongoDB (slide 249).
- The backend deployed on App Runner, and the database as Amazon DocumentDB, which speaks the MongoDB protocol (slides 252, 255).
- The frontend is only static files, so it is built and stored on S3 (slides 257-258).
- CloudFront as the one address in front of both: `/api` goes to the backend, every other path comes from S3 (slides 260, 262).
- Tearing it all down, because DocumentDB and CloudFront cost money (slide 264).

## What gets built here

| On the slides | Here | Container |
|---|---|---|
| DocumentDB | MongoDB | `day12-mongo` |
| Backend on App Runner | The notes API (`api/`, built into the image `day12-api:1`) | `day12-api` |
| React build | `frontend/`, built by esbuild in a `node` container | (build only) |
| S3 bucket | A bucket `day12-site` in a `moto` server, filled with `aws s3 sync` | `day12-moto` |
| CloudFront | Caddy, configured in `Caddyfile` | `day12-caddy` |

Only Caddy publishes a port: **8212**. The backend, the database and the bucket are reachable only from inside the Docker network `day12-net`.

The app is a small notes page: type a note, it is stored in MongoDB through the API, and the list is shown.

| File | What it does |
|---|---|
| `lab.sh` | Builds and starts everything, then exercises it. |
| `verify.sh` | 18 pass/fail checks. |
| `cleanup.sh` | Slide 264: removes the containers, network, image and build output. |
| `api/`, `frontend/`, `Caddyfile` | The sources. |

## Run it

From the Mac:

```bash
setup/run.sh day-12/lab.sh
```

```bash
setup/run.sh day-12/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 12` on the Mac | `18 passed, 0 failed` |
| 2 | Open http://<server>:8212 in your browser | "Day 12: full-stack notes", a text box and a list of notes |
| 3 | Type a note and press Add | The note appears at the top of the list |
| 4 | Open http://<server>:8212/api/notes | The notes as JSON: the same address serves the page and the API |
| 5 | Run `nc -z -w 3 $SERVER 27017 && echo open \|\| echo closed` | `closed`: the database is not reachable from outside |

Things to try yourself:

**The frontend and the backend are updated separately** (slide 257). Step 9 of the lab writes a file straight into the bucket, and it is served at once, with no deployment of the backend. `verify.sh` does the same with a random token. Open this to see the last thing written (a time from the lab, or a `release-...` token from a verify run):

http://<server>:8212/version.txt

**The backend keeps no data** (slides 252, 255). Add a note in the page, restart the backend, reload the page: the note is still there, because it is in MongoDB.

```bash
ssh $COURSE_HOST docker restart day12-api
```

## Differences from the slides

- **The bucket is public-read.** The slides' CloudFront reads a private bucket with its own credentials. Caddy here has none, so the objects are uploaded with `--acl public-read`. Nothing but Caddy can reach the bucket, because it is not published.
- **No pipeline.** The slides build the frontend and the backend image automatically (CodeBuild, ECR). Here `lab.sh` runs the build commands directly.
- **No domain, no HTTPS.** The slides serve the CloudFront distribution under two names (`www` and the bare domain). Here there is one address on port 8212 over plain HTTP.
- **The caching is minimal.** CloudFront caches at edge locations around the world. Caddy adds `Cache-Control` and gzip compression and has no cache of its own.
- **The database is MongoDB, not DocumentDB.** The slides point out that the code does not change, which is why this works.
- **A separate bucket server.** This day starts its own `moto` container instead of using the day 8 one, so the two days do not depend on each other.

## Without AWS

Each AWS service is replaced by a container, listed above. No AWS account or endpoint is used. The `aws` commands are the real AWS CLI, pointed at `moto`, which accepts any credentials in this setup.

The note on the failed run: the first `verify.sh` straight after the third `lab.sh` run reported 16 passed and 2 failed. I could not reproduce it: the next seven runs, including a fresh `lab.sh` followed at once by `verify.sh`, all passed 18/18. I did not find the cause.

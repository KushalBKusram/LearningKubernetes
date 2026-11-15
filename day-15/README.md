# Day 15: Docker Compose

**Status:** run on the server on 2026-11-14, twice (the lab is repeatable); all 17 checks in `verify.sh` pass, and the WordPress install page loads from the Mac. Ready for you to validate.

**Slides:** 301-315

## What the slides cover

- Starting several containers with separate `docker run` commands is tedious; Compose describes them in one `compose.yaml` and `docker compose up` creates a private network and starts them (slides 304-305).
- A little YAML: indentation for structure, `key: value` pairs, lists with `-` (slide 307).
- The main elements: `image`, `environment`, `ports` (no whitespace in `80:80`), `restart`, `volumes` (also listed at the top level) (slide 309).
- The commands: `up [--detach]`, `down` (volumes remain), `stop`, `start`, `pause`, `unpause`, `rm` (slide 311).
- Passwords out of the file: `${VAR}` plus a `.env` file kept out of the repository (slide 313).
- Healthchecks, so WordPress starts only once the database is up, using `depends_on` (slide 315). The slide also mentions restarting unhealthy containers with "autoheal"; see the differences below.

## What gets built here

| File | What it does |
|---|---|
| `compose.yaml` | WordPress + MariaDB, with healthchecks, `depends_on`, named volumes and `${...}` variables. |
| `.env.example` | The variable names, with placeholders. |
| `.gitignore` | Keeps `.env` out of a repository. |
| `lab.sh` | Generates `.env` with random passwords, then walks through `up`, `ps`, `stop`, `start`, `pause`, `unpause`, `down`, `up` again, `logs`, `exec`. |
| `verify.sh` | 17 pass/fail checks. |
| `cleanup.sh` | Takes the project down **with its volumes and data** and deletes `.env`. |

Left running after the lab (compose project `day15`):

| Service | Container | Port | Data |
|---|---|---|---|
| `db` | `day15-db-1` (MariaDB 10.11) | none | volume `day15-db-data` |
| `wordpress` | `day15-wordpress-1` | 8325 | volume `day15-wp-data` |

## Run it

From the Mac:

```bash
setup/run.sh day-15/lab.sh
```

```bash
setup/run.sh day-15/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 15` on the Mac | `17 passed, 0 failed` |
| 2 | Open http://<server>:8325 | The WordPress installation page (language choice). Nothing is installed yet; that is the starting point of a fresh site |
| 3 | Run `ssh $COURSE_HOST "cd ~/Projects/Kubernetes/day-15 && docker compose ps"` | Both services `Up ... (healthy)`, only WordPress with a port |
| 4 | Open `day-15/compose.yaml` and search for a password | There is none; only `${DB_PASSWORD}` style references |

Things to try yourself.

**Finish the WordPress setup, then prove `down` keeps data.** In the browser, complete the install (choose a language, a site title, a user). Then remove the containers and bring them back:

```bash
ssh $COURSE_HOST "cd ~/Projects/Kubernetes/day-15 && docker compose down && docker compose up --detach"
```

Reload the page after a few seconds: your site is still there, not the installer. The data lives on the two named volumes, not in the containers.

**Watch the healthcheck gate the start.** Stop the whole project, then start only WordPress. Compose starts the database first and waits for it to be healthy:

```bash
ssh $COURSE_HOST "cd ~/Projects/Kubernetes/day-15 && docker compose stop && docker compose up --detach wordpress"
```

## Differences from the slides

- The slides' compose file uses MySQL in the overview and MariaDB in the table. This uses MariaDB 10.11, which WordPress supports, and the image the server already has from day 13.
- The slides write `docker compose up` with passwords in the file first, then move them to `.env`. This goes straight to `.env`, generated with random values on every lab run and readable only by you. `${DB_PASSWORD:?...}` makes Compose refuse to start if a value is missing.
- Names are fixed so days do not collide: project `day15`, network `day15-net`, volumes `day15-db-data` and `day15-wp-data`, port 8325.
- Slide 315 also mentions restarting unhealthy containers automatically with "autoheal". Docker and Compose do not do this by themselves: a failing healthcheck only marks the container `unhealthy`. Day 16 builds that part, with a small auto-heal container.
- The lab does not run `docker compose rm` (slide 311) on its own, because `down` already removes the containers. It is the same command family and removes only stopped containers.

## Without AWS

Nothing on this day needs AWS.

# Day 02: Managing containers and running nginx

**Status:** run on the server on 2026-11-14, including the exercise; all 6 checks in `verify.sh` pass, and the edited page loads from the Mac. Ready for you to validate.

**Slides:** 25-55

## What the slides cover

- IP addresses, ports and `localhost` (slides 27-28).
- What a web server is; nginx (slides 30-32).
- Container ports are isolated until published with `-p host:container` (slides 33-34).
- Detached mode `-d`, and what `-i` and `-t` mean (slides 36-37).
- `docker container ls -as`, `stats`, `inspect`, `logs` (slide 39).
- Naming with `--name` (slide 41).
- `stop`, `start`, `rm` (slides 43-44).
- `docker run` always creates a new container; `--rm` (slides 46-47).
- Overriding the default program, and `docker exec` in a running container (slides 49-51).
- `docker create` and its immutable options (slide 53).
- Exercise: change the nginx start page (slide 55).

## What gets built here

| File | What it does |
|---|---|
| `lab.sh` | Walks through the commands above. Leaves `day02-nginx` running on port 8888. |
| `exercise.sh` | A solution to the slide 55 exercise, applied to `day02-nginx`. |
| `verify.sh` | Checks the port mapping, the container state and the edited page. |
| `cleanup.sh` | Removes the day 2 containers. |

## Run it

From the Mac:

```bash
setup/run.sh day-02/lab.sh
```

```bash
setup/run.sh day-02/exercise.sh
```

```bash
setup/run.sh day-02/verify.sh
```

Then open the page in a browser on the Mac. It should have a light gray background and the heading "Welcome to nginx in docker":

http://<server>:8888

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 02` on the Mac | `6 passed, 0 failed` |
| 2 | Open http://<server>:8888 | A light gray page headed "Welcome to nginx in docker" |
| 3 | Run `ssh $COURSE_HOST docker container ls -as` | `day02-nginx` with `0.0.0.0:8888->80/tcp` in the PORTS column |

One thing to try yourself, which shows that stopping a container does not lose its files (slide 43). Stop the container and reload the page: the browser cannot connect.

```bash
ssh $COURSE_HOST docker stop day02-nginx
```

Start it again and reload: the page is back, still gray, still with the edited heading.

```bash
ssh $COURSE_HOST docker start day02-nginx
```

## Doing the exercise by hand

`exercise.sh` uses `sed` so that it can run unattended. The slides do it with an editor. On the server:

```bash
docker exec -it day02-nginx bash
```

Inside the container: `apt update && apt install -y nano`, then `nano /usr/share/nginx/html/index.html`.

## Differences from the slides

- On the slides the browser and Docker are on the same laptop, so the address is `http://localhost:8888`. Here the container runs on the server, so `localhost` only works from the server itself. From the Mac, use the server's name.
- Docker publishes ports on all of the server's network interfaces, so port 8888 is also reachable from other devices on whatever network the server is connected to, not only over Tailscale. Run `cleanup.sh` when you are done if that matters.

## Without AWS

Nothing on this day needs AWS.

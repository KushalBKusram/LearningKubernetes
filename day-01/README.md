# Day 01: Containers, images and first runs

**Status:** run on the server on 2026-11-14; all 9 checks in `verify.sh` pass. Ready for you to validate.

**Slides:** 1-24

## What the slides cover

- Why containers exist: the dev environment should match production (slide 4).
- What a container is, and what Docker and Docker Desktop are (slides 6-8).
- First runs: `hello-world`, `ubuntu`, `node`, `python` (slide 10).
- Images come from a registry, Docker Hub by default (slide 12).
- An image is a stack of read-only layers; a container is an instance of it (slide 14).
- `docker image pull / history / inspect / ls` (slide 15).
- Tags select versions: `python`, `python:slim` (slide 17).
- `docker run` = pull + create + start (slide 19).
- Linux terminal basics (slide 23).

## What gets built here

| File | What it does |
|---|---|
| `lab.sh` | Runs every command from the slides, non-interactively, with the slide number next to each step. |
| `verify.sh` | Checks the results: images present, tags give different versions, a container cannot change its image. |

## Run it

From the Mac:

```bash
setup/run.sh day-01/lab.sh
```

```bash
setup/run.sh day-01/verify.sh
```

## Try the interactive versions yourself

The slides use `-it`, which needs a real terminal. On the server:

```bash
docker run -it --rm ubuntu
```

```bash
docker run -it --rm python
```

```bash
docker run -it --rm node
```

Leave each with `exit` or Ctrl+D.

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 01` on the Mac | `9 passed, 0 failed` |
| 2 | Run `ssh $COURSE_HOST docker image ls` | `hello-world`, `ubuntu`, `fedora`, `node`, and `python` with the tags `latest`, `slim` and `3.12-slim` |
| 3 | Run `ssh -t $COURSE_HOST docker run -it --rm python:3.12-slim` | A Python 3.12 prompt. Leave with `exit()` |

One thing to try yourself, which shows that a container cannot change its image (slide 14). Start an Ubuntu container, create a file, and leave:

```bash
ssh -t $COURSE_HOST docker run -it --rm ubuntu
```

Inside: `touch /mine.txt && ls /mine.txt`, then `exit`. Run the same command again and `ls /mine.txt` reports that the file does not exist.

## Differences from the slides

- The slides install Docker Desktop on a laptop. Here Docker Engine runs on the server, which is the install the slides cover on day 3.
- The slides mention `python:2` as an older version. The lab uses `python:3.12-slim` for the comparison, because the Python 2 image has been unmaintained since 2020.

## Without AWS

Nothing on this day needs AWS.

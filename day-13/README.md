# Day 13: Volumes

**Status:** run on the server on 2026-11-14, twice (the lab is repeatable); all 11 checks in `verify.sh` pass, and the nginx page loads from the Mac. Ready for you to validate.

**Slides:** 265-281

## What the slides cover

- Containers are never updated; you create a new one and throw the old one away (slide 268).
- A volume maps container data to a directory Docker manages on the host, and can be shared by several containers (slide 270).
- `docker volume create / ls / inspect / rm / prune`; a volume cannot be renamed (slide 271).
- Connecting a volume with `--mount type=volume,...` or `-v name:/path`; a missing volume is created automatically; a name without a leading `/` is a volume, with one it is a bind mount (slides 273-274).
- Images such as MariaDB create a volume on their own, with a generated name, so name your own (slide 276).
- `VOLUME` in a Dockerfile, which cannot be undone later (slide 278).
- Updating a database: new container, same volume, `MARIADB_AUTO_UPGRADE=1` (slides 280-281).

## What gets built here

| File | What it does |
|---|---|
| `lab.sh` | Walks through each point above. Ends with MariaDB 10.11 writing three rows, then MariaDB `latest` taking over the same volume and reading them. |
| `volume-demo/Dockerfile` | An nginx image with `VOLUME /usr/share/nginx/html`. |
| `verify.sh` | 11 pass/fail checks. |
| `cleanup.sh` | Removes the containers, **the volumes and the data in them**, the demo image and the scratch folder. |

Left running after the lab:

| Container | Port | Data |
|---|---|---|
| `day13-nginx` | 8313 | volume `day13-nginx-vol` |
| `day13-mariadb` | none | volume `day13-mariadb-vol` |

The database root password is generated on every run into `day-13/.work/db.env` on the server (readable by you only). It is passed with `--env-file`, so it does not appear in any command line.

## Run it

From the Mac:

```bash
setup/run.sh day-13/lab.sh
```

```bash
setup/run.sh day-13/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 13` on the Mac | `11 passed, 0 failed` |
| 2 | Open http://<server>:8313/hello.txt | `stored on a volume, not in a container` |
| 3 | Run `ssh $COURSE_HOST docker volume ls --filter name=day13-` | `day13-mariadb-vol` and `day13-nginx-vol` |
| 4 | Read steps 9 and 10 of the lab output | MariaDB `10.11` then `13.x`, and the same three rows both times |

Things to try yourself.

**The data outlives the container.** Delete the web container and start a new one on the same volume. The file is still served.

```bash
ssh $COURSE_HOST "docker rm -f day13-nginx && docker run -d --name day13-nginx -p 8313:80 -v day13-nginx-vol:/usr/share/nginx/html nginx"
```

Reload http://<server>:8313/hello.txt.

**Ask the database what it holds**, after it was upgraded:

```bash
ssh $COURSE_HOST "docker exec day13-mariadb sh -c 'mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" -e \"SELECT VERSION(); SELECT * FROM course.notes\"'"
```

## Differences from the slides

- The slides use `-e MARIADB_ROOT_PASSWORD=password123`. The lab generates a random password and passes it with `--env-file`, so no password sits in a command line or in the repository.
- The slides call the old version "outdated" without naming it. The lab uses `mariadb:10.11` as the old one and `mariadb:latest` (13.x at the time of writing) as the new one. The jump is large, which is why `MARIADB_AUTO_UPGRADE=1` is set, as slide 280 advises. Slide 280 also warns that the upgraded data cannot normally be downgraded; that is true here too.
- The slides also show `docker volume prune`. The lab does not run it, because it deletes every unused volume on the machine, not only this day's.

## Without AWS

Nothing on this day needs AWS.

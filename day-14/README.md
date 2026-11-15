# Day 14: Docker networking

**Status:** run on the server on 2026-11-14, twice (the lab is repeatable); all 17 checks in `verify.sh` pass, and mongo-express loads from the Mac. Ready for you to validate.

**Slides:** 282-300

## What the slides cover

- Services run in separate containers, so they need a network to talk (slide 285).
- The three default networks, `bridge`, `host` and `none`, and `docker network ls / inspect` (slide 286).
- `bridge`: a private subnet (172.17.0.0/16), the default for new containers (slide 288).
- `host`: no isolation, the container uses the host's network; `-p` no longer applies; Linux only (slide 290).
- `none`: loopback only, no way in or out (slide 291).
- Custom bridge networks with `docker network create`, `--network`, and `docker network rm / prune` (slide 293).
- `docker network connect / disconnect` on a running container (slide 294).
- On the default bridge containers reach each other by IP; on a custom network they also resolve each other's **names** (slide 296).
- The task: MongoDB plus mongo-express on a custom network `mongo-net`, with a volume on `/data/db` and mongo-express published on a host port (slides 298-300).

## What gets built here

| File | What it does |
|---|---|
| `lab.sh` | One step per slide topic, then the MongoDB + mongo-express task. |
| `verify.sh` | 17 pass/fail checks. |
| `cleanup.sh` | Removes the containers, networks, **the volume and the data in it**, and the scratch folder. |

Left running after the lab:

| Name | What | Port |
|---|---|---|
| `day14-mongo-net` | custom bridge network | |
| `day14-mongo` | MongoDB, data on volume `day14-mongo-vol` | none: nothing outside the network can reach it |
| `day14-express` | mongo-express | 8314 (the container's 8081) |

## Run it

From the Mac:

```bash
setup/run.sh day-14/lab.sh
```

```bash
setup/run.sh day-14/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 14` on the Mac | `17 passed, 0 failed` |
| 2 | Open http://<server>:8314 | The mongo-express page, with a database called `course` in the list |
| 3 | Run `ssh $COURSE_HOST docker port day14-mongo` | Nothing: MongoDB publishes no port |
| 4 | Read step 2 and step 3 of the lab output | On the default bridge the name `day14-a` does not resolve; on `day14-net` it resolves to an address |

Things to try yourself.

**Names only work on a custom network.** Resolve the database's name from a container on the default bridge, then from one on its own network. The first prints nothing, the second prints an address:

```bash
ssh $COURSE_HOST "docker run --rm ubuntu getent hosts day14-mongo; echo exit=\$?"
```

```bash
ssh $COURSE_HOST "docker run --rm --network day14-mongo-net ubuntu getent hosts day14-mongo"
```

**The database survives its container.** Replace the MongoDB container with a new one on the same volume, then reload mongo-express: the `course` database is still there.

```bash
ssh $COURSE_HOST "docker rm -f day14-mongo && docker run -d --name day14-mongo --network day14-mongo-net -v day14-mongo-vol:/data/db mongo"
```

## Differences from the slides

- The slides name the network `mongo-net`, the volume `mongo-vol`, the database container `my-mongo` and publish mongo-express on a port of your choice. Here every name starts with `day14-` and the port is 8314, so days do not collide.
- Host network (slide 290): nginx would listen on port 80 of the server, which another day uses. The lab gives nginx a small config that listens on 8315 instead. That also shows the point of the slide: with `--network host` the container's ports are the server's own ports and `-p` is not used.
- The `ubuntu` image has no `ping` or `curl`, so the lab tests connectivity with `getent hosts` (name lookup) and bash's `/dev/tcp` (open a connection).
- mongo-express is started with `ME_CONFIG_BASICAUTH=false`, so there is no login page. That is fine on a lab machine and would not be in production. The connection is given with `ME_CONFIG_MONGODB_URL`, the variable the current image documents.
- The `mongo` image declares a second volume, `/data/configdb`, which Docker creates with a generated name. `cleanup.sh` removes it with the container (`docker rm -v`).
- The lab does not run `docker network prune`, because it deletes every unused network on the machine, not only this day's.

## Without AWS

Nothing on this day needs AWS. On day 11 these same Docker networks stand in for a VPC and its subnets.

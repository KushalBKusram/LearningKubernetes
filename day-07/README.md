# Day 07: Your own registry and CPU architectures

**Status:** run on the server on 2026-11-14; all 21 checks in `verify.sh` pass. Ready for you to validate.

**Slides:** 158-168. It needs the image `day06-app` from day 6.

## What the slides cover

- Why run your own registry: share images and deploy them to other machines (slide 159).
- Why CPU architecture matters: a Raspberry Pi, ARM servers on AWS, Macs with Apple chips (slide 161).
- ARM (`linux/arm64`) versus x86 (`linux/amd64`); containers share the host kernel, so an image must be built per architecture; `--platform` and the cost of emulation (slides 163-164).
- Starting a registry with `docker run -d -p 5000:5000 registry:2`; `docker image tag`, `docker push`, `docker pull` (slide 166).
- Protecting it with HTTP basic authentication and an `.htpasswd` file (slide 168).

## What gets built here

| File | What it does |
|---|---|
| `lab.sh` | Starts an open registry, pushes and pulls `day06-app`, adds a password, then covers architectures and a multi-platform build. Leaves `day07-registry` running. |
| `verify.sh` | 21 pass/fail checks. |
| `cleanup.sh` | Removes the registry container and the images it made. `--all` also removes the data volume and the password files. |

The registry:

| | |
|---|---|
| Container | `day07-registry` (`registry:2`) |
| Address | `localhost:5000`, on the server only |
| User | `courselab` |
| Password | Generated on the first run, kept in `~/.course/registry-password` on the server (mode 600). The lab never prints it. |
| Data | The named volume `day07-registry-data`, so images survive recreating the container |

Day 9 pushes to this registry.

## Run it

From the Mac:

```bash
setup/run.sh day-07/lab.sh
```

```bash
setup/run.sh day-07/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 07` on the Mac | `21 passed, 0 failed` |
| 2 | Run `ssh $COURSE_HOST "curl -s -o /dev/null -w '%{http_code}\n' localhost:5000/v2/_catalog"` | `401`: the registry wants a password |
| 3 | Run `ssh $COURSE_HOST 'curl -s -u courselab:$(cat ~/.course/registry-password) localhost:5000/v2/_catalog'` | `{"repositories":["day06-app","day07-multiarch"]}` (day 9 adds more) |
| 4 | Run `ssh $COURSE_HOST "docker buildx imagetools inspect localhost:5000/day07-multiarch:1"` | One image name with two entries: `linux/amd64` and `linux/arm64` |
| 5 | Run `ssh $COURSE_HOST "docker run --rm --platform linux/arm64 hello-world:linux"` | `exec /hello: exec format error`. The arm64 image cannot run on this x86 machine without emulation (slide 164) |

Things to try yourself.

**Push and pull by hand.** Tag the image under a new name, push it, and look at the catalog:

```bash
ssh $COURSE_HOST 'docker tag day06-app localhost:5000/my-copy:test && docker push localhost:5000/my-copy:test'
```

```bash
ssh $COURSE_HOST 'curl -s -u courselab:$(cat ~/.course/registry-password) localhost:5000/v2/_catalog'
```

**Data survives the container.** Remove the registry container and run the lab again: the images pushed earlier are still listed, because they live in the volume.

```bash
ssh $COURSE_HOST "docker rm -f day07-registry"
```

## Differences from the slides

- The registry is published on `127.0.0.1:5000`, not `5000:5000` as on the slide. Basic authentication sends the password unencrypted over plain HTTP, so the registry is not offered to the network. Docker allows plain HTTP to `localhost` without any extra configuration. Reaching it from another machine would need TLS, which this lab does not set up.
- The slides show `htpasswd -Bn myuser`, which asks for the password on a terminal. The lab passes it on stdin (`-Bin`) so it can run unattended and the password is not on a command line.
- `docker login` stores the credentials in `~/.docker/config.json` on the server, unencrypted. Docker prints a warning about this. `cleanup.sh` logs out.
- The slides leave the architecture discussion at the concept. The lab also shows it: the arm64 variant of `hello-world` is pulled and fails with `exec format error`. This machine has no QEMU emulation installed. Installing it would register a handler in the server's kernel, which is a system change, so it was left out.
- The multi-platform build uses an image with no `RUN` steps. A real arm64 build of the Node app would need emulation to run `npm ci`.

## Without AWS

Nothing on this day needs AWS. This registry is also the stand-in for Amazon ECR, which day 9 covers: the same push and pull, with `courselab` and a password standing in for IAM credentials.

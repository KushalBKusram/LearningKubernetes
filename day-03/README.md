# Day 03: Docker on a Linux server

**Status:** run on the server on 2026-11-14; all 7 checks in `verify.sh` pass, and the Apache page loads from the Mac. Starting containers at boot is tested without a reboot by `boot-test.sh` (13 of 13 checks pass), which restarts a nested Docker daemon instead of the machine. The `apt` steps need your sudo password and have not been done. Ready for you to validate.

**Slides:** 56-97. Slide 57 is the only one that names its day ("Day 3").

## What the slides cover

- AWS and EC2: renting a virtual server (slides 60-64).
- SSH, and key pairs for login (slides 66-68).
- Linux users, `root` and `sudo` (slides 70-71).
- Keeping the server up to date with `apt` (slides 73-78).
- Docker's client and daemon architecture (slides 80-83).
- Installing Docker from Docker's own repository (slide 85).
- Restart policies: `no`, `on-failure`, `always`, `unless-stopped` (slides 87-88).
- Optional: Raspberry Pi or a VirtualBox VM as the server (slides 90-96).

## Without AWS

The slides rent an Ubuntu EC2 instance. The server takes its place: it is a real Ubuntu server that you reach over SSH with a key pair, which is the same situation the slides set up. Slide 60 itself says AWS is not required for this chapter.

| On the slides | Here |
|---|---|
| EC2 instance running Ubuntu | The server (Ubuntu 26.04, x86_64) |
| `ssh ubuntu@<public-ip>` with an AWS key pair | `ssh $COURSE_HOST`, using the ed25519 key already on the Mac |
| EC2 security group opening port 80 | Docker's published ports on the server |
| Public IP address | The server's Tailscale name |

What this does not give you: the EC2 console, instance types, and the free-tier and billing side of AWS.

## What gets built here

| File | What it does |
|---|---|
| `../setup/install-docker.sh` | The Docker install from slide 85. This had to happen before day 1, because the server runs everything. |
| `lab.sh` | Shows the client/daemon split, runs Apache with `--restart unless-stopped`, and shows the policy restarting it. |
| `verify.sh` | Checks Apache is serving, the restart policy is set and a restart happened. |
| `cleanup.sh` | Removes the day 3 container. |

## Run it

From the Mac:

```bash
setup/run.sh day-03/lab.sh
```

```bash
setup/run.sh day-03/verify.sh
```

Then open http://<server>:8080 on the Mac. It should say "It works!".

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 03` on the Mac | `6 passed, 0 failed` |
| 2 | Open http://<server>:8080 | "It works!" |
| 3 | Run `ssh $COURSE_HOST "docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' day03-apache"` | `unless-stopped` |
| 4 | Run `setup/run.sh day-03/boot-test.sh` on the Mac (takes about a minute) | `13 passed, 0 failed`, and the before/after tables described below |

One thing to try yourself, which shows the restart policy working (slide 87). End Apache's main process:

```bash
ssh $COURSE_HOST "docker exec day03-apache bash -c 'kill 1'"
```

Reload the page: it is back within a second or two. The restart counter has gone up by one:

```bash
ssh $COURSE_HOST "docker inspect -f '{{.RestartCount}}' day03-apache"
```

## Testing "comes back on boot" without a reboot

Slide 57's goal is a container that is started again when the server boots. A real reboot needs sudo, and it would take down everything else running on the server. `boot-test.sh` tests the same mechanism instead. Docker decides what to start by reading each container's restart policy when the daemon starts, and systemd starts the daemon at boot.

What the script does:

1. **Real daemon:** reports whether `docker.service` and `containerd.service` are enabled at boot, which is what makes the daemon start after a reboot. On the server both are `enabled`.
2. **Real containers:** lists every running container with its restart policy and whether it would come back.
3. **Nested daemon:** runs a second Docker daemon in a throwaway container (`docker:dind`) with five nginx containers inside, each with a different policy. It then does a graceful shutdown and restart of that daemon, and a kill and restart (a power cut), and compares before and after.

What comes back, in both rounds:

| Container inside the nested daemon | After the daemon restarts |
|---|---|
| `unless-stopped`, running | running again |
| `always`, running | running again |
| `no`, running | stays down |
| `unless-stopped`, stopped by hand | stays down |
| `always`, stopped by hand | running again (slide 87: `always` restarts it at the next daemon start) |

The nested daemon needs `--privileged`, so it exists for about a minute and is removed at the end.

What this does not prove: that the server actually boots into a working Docker. Enabled units are the strongest evidence short of rebooting, and a reboot remains the only complete test.

### Restart policies across the whole course

The slides leave Docker's default policy (`no`) on most containers. After the first run of this test showed that, every lab that leaves a container running now starts it with `--restart unless-stopped`, so everything built in this course comes back after a reboot. Section 2 of the script lists the real containers and its results include a check that none is left without a policy.

- **Plain containers:** `unless-stopped` on every one that is left running (days 2 to 16 and 24).
- **Swarm tasks (days 17 and 18):** Swarm starts its own tasks again when the daemon starts, so the script leaves them out.
- **The Kubernetes clusters (`course`, `eks`):** `kind` starts its node containers with `on-failure`, which does not restart them after a clean shutdown. `day-19/lab.sh` and `day-24/lab.sh` change them to `unless-stopped` after creating the clusters. This was tested by restarting the node containers: both clusters came back with all pods running, but `eks` took a few minutes and some pods crashed a few times while the API server came up. Allow a few minutes after a reboot before running a check.

## Steps that need your sudo password

I cannot type your password, so these are yours to run on the server.

Update the system (slide 75):

```bash
sudo apt update && sudo apt upgrade
```

Install and remove a package (slides 77-78):

```bash
sudo apt install cowsay && cowsay "Hello from Ubuntu!"
```

Optional, the one complete test of slide 57's goal. It restarts everything on the server, so do it last. Reboot, then load the Apache page again:

```bash
sudo reboot
```

## Optional: the client and the daemon on different machines (slide 83)

Slide 83 says the Docker client and daemon do not have to be on the same machine. The Mac already has a Docker client, so it can drive the server's daemon over SSH. This adds a Docker context on the Mac, so it is left for you to decide:

```bash
docker context create course-server --docker "host=ssh://$COURSE_HOST"
```

```bash
docker --context course-server ps
```

## Differences from the slides

- The slides generate a new key pair with `ssh-keygen -t ed25519`. The Mac already has one and already logs in to the server with it, so nothing is generated.
- The Raspberry Pi and VirtualBox chapters are skipped. They are alternatives to AWS, and the server already fills that role.

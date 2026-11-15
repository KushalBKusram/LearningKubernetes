# Day 11: Networking in AWS

**Status:** run twice on the server on 2026-11-14; all 22 checks in `verify.sh` pass. Ready for you to validate. It needs the moto server from day 8 for the AWS half.

**Slides:** 232-247

## What the slides cover

- A VPC: a private virtual network for your resources (slide 234).
- Subnets: a slice of the VPC's address range, each in one availability zone (slides 236-237).
- Public versus private subnets: public means a route to an Internet Gateway (slides 239, 241).
- Network ACLs: stateless firewalls on a subnet (slide 243).
- Security groups: stateful firewalls on an instance, several per instance (slide 245).
- The conditions for one resource to reach another: route, network ACL, security groups, IAM (slide 247).

## What gets built here

Two halves that describe the same layout.

**Part 1, Docker networks (what actually moves packets):**

| AWS | Docker |
|---|---|
| Public subnet `10.211.1.0/24` | Network `day11-public`, an ordinary bridge with a gateway |
| Private subnet `10.211.2.0/24` | Network `day11-private`, created with `--internal`: no route out, nothing publishable |
| Web server | `day11-web` (nginx), in both networks, port 8211 published |
| Database | `day11-db` (MariaDB), in the private network only |
| A machine that should not get in | `day11-outsider`, in the public network only |
| Security group: web allows 80 from anywhere | Only port 80 of `day11-web` is published |
| Security group: db allows 3306 from the web group | `day11-db` shares a network with `day11-web` and nothing else |

**Part 2, AWS API calls (what the objects look like on AWS):** the real AWS CLI creates the same layout in the day 8 moto server: a VPC `10.211.0.0/16`, two subnets in two zones, an Internet Gateway, a public and a private route table, a network ACL, and security groups `day11-web` and `day11-db`.

| File | What it does |
|---|---|
| `lab.sh` | Builds both halves, prints a reachability table, and walks through the slide 247 checklist. |
| `verify.sh` | 22 pass/fail checks. |
| `cleanup.sh` | Removes the containers, networks and the moto objects. |
| `common.sh`, `web/` | Helpers and the web page. |

## Run it

Run day 8 first, then from the Mac:

```bash
setup/run.sh day-11/lab.sh
```

```bash
setup/run.sh day-11/verify.sh
```

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 11` on the Mac | `22 passed, 0 failed` |
| 2 | Open http://<server>:8211 | A page headed "Day 11: the web tier" |
| 3 | Run `nc -z -w 3 $SERVER 3306 && echo open \|\| echo closed` on the Mac | `closed`: the database cannot be reached from outside |
| 4 | Read the table in step 4 of the lab output | Seven rows, each marked `ok` |

Things to try yourself:

**Break the private subnet's isolation and watch the outsider get in.** Put the outsider into the private network, test, and take it out again:

```bash
ssh $COURSE_HOST 'docker network connect day11-private day11-outsider && docker exec day11-outsider timeout 3 bash -c "echo > /dev/tcp/day11-db/3306" && echo reached'
```

```bash
ssh $COURSE_HOST 'docker network disconnect day11-private day11-outsider'
```

**See what the AWS side recorded:**

```bash
setup/run.sh day-08/aws-as.sh cli-admin ec2 describe-route-tables --filters Name=tag:Name,Values=day11-public-rt --query 'RouteTables[0].Routes'
```

The public route table has a `0.0.0.0/0` route to an `igw-...` gateway; the private one has none.

## Differences from the slides

- **The slides' diagrams use the default VPC, `172.31.0.0/16`.** This day uses `10.211.0.0/16`, because other days already use the more common ranges on the same Docker host.
- **Docker has no security groups or network ACLs.** Part 1 gets the same effect from which network a container joins and which ports are published. Statelessness (ACL) versus statefulness (security group) is not something Docker lets you observe; part 2 only shows the rules that make the difference (the ACL needs an explicit outbound rule for the answer).
- **Two zones.** The slides draw three subnets in three zones; this day builds two, one public and one private.
- **No instances in the VPC.** The containers in part 1 and the objects in part 2 are separate; nothing links a moto instance to a container.

## Without AWS

- The Docker half does real network isolation on the server.
- The AWS half runs against the moto server from day 8. moto stores and returns the VPC, subnets, routes, ACLs and security groups, but it does not route traffic or enforce them. The Docker half is the part that proves reachability.
- The slides' last condition, IAM permissions, was covered on day 8.

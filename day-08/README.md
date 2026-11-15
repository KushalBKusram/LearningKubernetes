# Day 08: AWS crash course and IAM

**Status:** run twice on the server on 2026-11-14; all 17 checks in `verify.sh` pass. Ready for you to validate. The AWS CLI is the real one, but it talks to a mock of AWS, so permission enforcement is only partly like AWS (see "Without AWS").

**Slides:** 169-196

## What the slides cover

- Regions and availability zones (slides 172-173).
- EC2 as virtual servers (slide 175).
- The AWS command line and its three environment variables (slides 177, 188).
- IAM users, the root user, groups and policies (slides 179, 183).
- The structure of an ARN (slide 181).
- A second user with read-only EC2 access (slides 186, 188).
- A policy limited to one specific instance (slide 190).
- A managed policy shared by several users, versus an inline policy (slide 192).
- Roles, so an instance needs no stored access keys (slides 194, 196).

## What gets built here

| File | What it does |
|---|---|
| `lab.sh` | Starts a fresh `moto` server (a mock of the AWS APIs) in a container, then walks through the slides with the real AWS CLI. |
| `policies/` | The policy documents the lab uses (JSON, as on the slides). |
| `common.sh` | Shared helpers: the `aws` function (the CLI from the `amazon/aws-cli` image, pointed at moto) and key handling. |
| `aws-as.sh` | Runs one CLI command as one of the lab's users, for your own experiments. |
| `verify.sh` | 17 pass/fail checks. |
| `cleanup.sh` | Removes the moto container, its network and the stored keys. |

What exists afterwards, all inside the moto server: users `cli-admin`, `monitor-script` and `dashboard`; instances `web-1` and `web-2`; the managed policy `Ec2MonitorAndRestart`; the role and instance profile `Ec2MonitorRole`; two S3 buckets.

## Run it

From the Mac:

```bash
setup/run.sh day-08/lab.sh
```

```bash
setup/run.sh day-08/verify.sh
```

The server listens on port 8200 of the server. The access keys in `day-08/.work/` only work against this mock.

## How to validate

| # | Do this | You should see |
|---|---|---|
| 1 | Run `setup/validate.sh 08` on the Mac | `17 passed, 0 failed` |
| 2 | Run `setup/run.sh day-08/aws-as.sh cli-admin sts get-caller-identity` | An ARN ending in `user/cli-admin`, account `123456789012` |
| 3 | Run `setup/run.sh day-08/aws-as.sh monitor-script ec2 describe-instances --query 'Reservations[].Instances[].InstanceId'` | Two instance ids |
| 4 | Run `setup/run.sh day-08/aws-as.sh monitor-script iam list-users` | `AccessDenied ... not authorized to perform: iam:ListUsers` |
| 5 | Open http://<server>:8200/moto-api/ | The moto dashboard page |

Things to try yourself:

**Same account, two sets of rights.** Run the same command as both users and compare. The admin may list users, the monitor user may not:

```bash
setup/run.sh day-08/aws-as.sh cli-admin iam list-users --query 'Users[].UserName'
```

**Slide 196's point about roles.** The temporary key of a role starts with `ASIA`, a user's key with `AKIA`, and the temporary one comes with a session token and an expiry time:

```bash
setup/run.sh day-08/aws-as.sh cli-admin sts assume-role --role-arn arn:aws:iam::123456789012:role/Ec2MonitorRole --role-session-name me
```

## Differences from the slides

- **No console.** The slides click through the AWS console for the root user. Here the first three API calls to moto are unauthenticated (`INITIAL_NO_AUTH_ACTION_COUNT=3`) and play that part: they create the first user and its policy and key.
- **The slides' own demo is partly shown.** The slides let an EC2 instance read other EC2 instances. Here that is the `monitor-script` user and the `Ec2MonitorRole` role; no machine runs anywhere, moto only records the instances.
- **The role needs the calling user in its trust policy.** On AWS, an EC2 instance gets the role through its instance profile. moto has no instance to do that, so the lab asks for temporary credentials with `sts assume-role` as `cli-admin`, and moto only allows that when the trust policy names `cli-admin` (`policies/trust-ec2.template.json`).
- **Region.** The lab uses `eu-west-3` (Paris), the region of the example ARN on slide 181.

## Without AWS

Everything on this day runs against `moto`, an open-source mock of the AWS APIs, in a container. No AWS account or endpoint is involved.

moto stores IAM objects and does check them, but it is not AWS:

- It checks the **action** of a request. Reading EC2 is allowed, stopping an instance is refused, and IAM calls are refused for the monitor user. That matches AWS.
- It does **not** evaluate EC2 resource ARNs. The slide 190 policy allows stopping one instance only. On AWS, `monitor-script` could stop `web-1` and not `web-2`; moto refuses both (the lab shows this). You still write and read the real policy document.
- It does check S3 resources, so the same one-resource idea is demonstrated with buckets: the policy allows reading `day08-reports` and nothing else.
- Instances, users and policies live in the server's memory and disappear when the container is removed or the lab is run again.

#!/usr/bin/env bash
# Day 08 lab: AWS crash course and IAM (slides 169-196), without an AWS account.
# The AWS CLI is the real one. It talks to a moto server, a mock of the AWS APIs,
# running in a container on the server. Nothing here reaches AWS.
# Safe to run more than once: it starts a fresh moto server every time.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./common.sh
need_docker

# Run a command that must be refused, and show the refusal.
expect_denied() {
  local out
  if out=$("$@" 2>&1); then
    echo "  UNEXPECTED: this was allowed"
    return 1
  fi
  echo "$out" | grep -E 'ERROR|error|failed' | head -1 | sed 's/^ *//; s/^/  refused: /'
}

docker rm -f day08-moto >/dev/null 2>&1 || true
docker network inspect day08-net >/dev/null 2>&1 || docker network create day08-net >/dev/null
rm -rf "$work"
mkdir -p "$work"

step "1. A stand-in for the AWS account: the moto server"
# INITIAL_NO_AUTH_ACTION_COUNT=3: the first three API calls need no valid
# credentials (they play the root user in the AWS console). After that, moto
# checks access keys and evaluates IAM policies.
run docker run -d --restart unless-stopped --name day08-moto --network day08-net -p 8200:5000 \
  -e INITIAL_NO_AUTH_ACTION_COUNT=3 motoserver/moto
for _ in $(seq 1 30); do
  curl -s -o /dev/null -m 2 http://localhost:8200/moto-api/ && break
  sleep 1
done
echo "moto answers on port 8200. Account id: $ACCOUNT"

step "2. The root user creates a user for the command line (slides 177-179)"
echo "On AWS you would do this in the console, logged in as the root user."
export AWS_ACCESS_KEY_ID=root-user-in-the-console AWS_SECRET_ACCESS_KEY=not-a-real-key
run aws iam create-user --user-name cli-admin --query 'User.Arn' --output text
run aws iam put-user-policy --user-name cli-admin --policy-name FullAccess --policy-document file://policies/admin.json
create_key cli-admin
echo
echo "From now on moto checks credentials. An unknown access key is rejected:"
expect_denied aws ec2 describe-regions

step "3. The three environment variables of the AWS CLI (slide 188)"
use_user cli-admin
echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:0:8}...  AWS_SECRET_ACCESS_KEY=(hidden)  AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION"
echo "Who am I?"
run aws sts get-caller-identity --output table

step "4. Regions and availability zones (slides 172-173)"
regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text | tr '\t' '\n')
echo "Regions known to the API: $(echo "$regions" | wc -l). The slides' examples are among them:"
echo "$regions" | grep -E '^(us-east-1|eu-central-1|ap-southeast-2|eu-west-3)$' | sed 's/^/  /'
echo "Availability zones of our region. The zone is the region plus a letter:"
run aws ec2 describe-availability-zones --query 'AvailabilityZones[].[ZoneName,RegionName,State]' --output table
echo "Another region has its own zones:"
run aws ec2 describe-availability-zones --region us-east-1 --query 'AvailabilityZones[].ZoneName' --output text

step "5. Virtual servers: two EC2 instances (slide 175)"
echo "moto only records these instances. No machine is started."
ami=$(aws ec2 describe-images --query 'Images[0].ImageId' --output text)
for name in web-1 web-2; do
  run aws ec2 run-instances --image-id "$ami" --instance-type t3.micro \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name}]" \
    --query 'Instances[0].InstanceId' --output text
done
web1=$(instance_id web-1)
web2=$(instance_id web-2)
echo "\$ aws ec2 describe-instances   (name, id, state, availability zone)"
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,State.Name,Placement.AvailabilityZone]' \
  --output table

step "6. ARNs: the full name of a resource (slide 181)"
user_arn=$(aws iam get-user --user-name cli-admin --query 'User.Arn' --output text)
web1_arn="arn:aws:ec2:$AWS_DEFAULT_REGION:$ACCOUNT:instance/$web1"
for arn in "$web1_arn" "$user_arn"; do
  echo "$arn"
  IFS=: read -r _ partition service region account resource <<<"$arn"
  printf '  partition=%s  service=%s  region=%s  account=%s  resource=%s\n' \
    "$partition" "$service" "${region:-(none: IAM is global)}" "$account" "$resource"
done

step "7. A second user with read-only access to EC2 (slide 186)"
run aws iam create-user --user-name monitor-script --query 'User.Arn' --output text
echo "Its inline policy, policies/ec2-read-only.json, allows only ec2:Describe*."
run aws iam put-user-policy --user-name monitor-script --policy-name monitoring --policy-document file://policies/ec2-read-only.json
create_key monitor-script

step "8. Working as the second user (slide 188)"
use_user monitor-script
echo "Now using the access key of: $(aws sts get-caller-identity --query Arn --output text)"
echo "Reading is allowed:"
run aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text
echo "Changing anything is not:"
echo "\$ aws ec2 stop-instances --instance-ids $web1"
expect_denied aws ec2 stop-instances --instance-ids "$web1"
echo "\$ aws iam list-users"
expect_denied aws iam list-users

step "9. Customizing the policy: stop and start one specific instance (slide 190)"
use_user cli-admin
sed "s|__INSTANCE_ARN__|$web1_arn|" policies/ec2-read-and-restart.template.json >"$work/ec2-read-and-restart.json"
echo "The new statement names one instance by its ARN:"
grep -A4 'StopAndStartOneInstanceOnly' "$work/ec2-read-and-restart.json" | sed 's/^/  /'
run aws iam put-user-policy --user-name monitor-script --policy-name monitoring --policy-document file://.work/ec2-read-and-restart.json
echo
echo "On AWS, monitor-script could now stop web-1 and nothing else."
echo "moto cannot show this. It evaluates the action of a request but not EC2 resource ARNs, so it refuses both:"
use_user monitor-script
echo "\$ aws ec2 stop-instances --instance-ids $web1    (web-1: AWS would allow this)"
expect_denied aws ec2 stop-instances --instance-ids "$web1" || true
echo "\$ aws ec2 stop-instances --instance-ids $web2    (web-2: AWS would refuse this too)"
expect_denied aws ec2 stop-instances --instance-ids "$web2"
echo
echo "The same idea where moto does check the resource: S3. The policy allows reading one bucket only."
use_user cli-admin
echo "all systems normal" >"$work/status.txt"
aws s3 mb s3://day08-reports >/dev/null
aws s3 mb s3://day08-private >/dev/null
aws s3 cp --quiet .work/status.txt s3://day08-reports/status.txt
aws s3 cp --quiet .work/status.txt s3://day08-private/status.txt
use_user monitor-script
echo "\$ aws s3 cp s3://day08-reports/status.txt -     (named in the policy)"
echo "  $(aws s3 cp s3://day08-reports/status.txt -)"
echo "\$ aws s3 cp s3://day08-private/status.txt -     (not named in the policy)"
expect_denied aws s3 cp s3://day08-private/status.txt -

step "10. A managed policy that several users can share (slide 192)"
use_user cli-admin
echo "So far the policy was inline: part of one user. A managed policy exists by itself and can be attached to many."
policy_arn=$(aws iam create-policy --policy-name Ec2MonitorAndRestart \
  --policy-document file://.work/ec2-read-and-restart.json --query 'Policy.Arn' --output text)
echo "Created: $policy_arn"
run aws iam attach-user-policy --user-name monitor-script --policy-arn "$policy_arn"
run aws iam delete-user-policy --user-name monitor-script --policy-name monitoring
run aws iam create-user --user-name dashboard --query 'User.Arn' --output text
run aws iam attach-user-policy --user-name dashboard --policy-arn "$policy_arn"
echo "Who uses this policy?"
run aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyUsers[].UserName' --output text
use_user monitor-script
echo "monitor-script still works, now through the managed policy:"
run aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --output text

step "11. Roles: no stored access keys on the instance (slides 194-196)"
use_user cli-admin
echo "The role's trust policy says who may assume it: the EC2 service. On AWS an instance profile is enough."
echo "moto only lets a user assume a role that names that user, so cli-admin is named too (policies/trust-ec2.template.json):"
sed "s|__CALLER_ARN__|$user_arn|" policies/trust-ec2.template.json >"$work/trust-ec2.json"
grep -E 'Service|AWS' "$work/trust-ec2.json" | sed 's/^ */  /'
run aws iam create-role --role-name Ec2MonitorRole --assume-role-policy-document file://.work/trust-ec2.json --query 'Role.Arn' --output text
run aws iam attach-role-policy --role-name Ec2MonitorRole --policy-arn "$policy_arn"
echo "An instance profile carries the role onto an instance:"
run aws iam create-instance-profile --instance-profile-name Ec2MonitorRole --query 'InstanceProfile.Arn' --output text
run aws iam add-role-to-instance-profile --instance-profile-name Ec2MonitorRole --role-name Ec2MonitorRole
run aws ec2 associate-iam-instance-profile --instance-id "$web1" --iam-instance-profile Name=Ec2MonitorRole \
  --query 'IamInstanceProfileAssociation.[InstanceId,IamInstanceProfile.Arn]' --output text
echo
echo "With the role, web-1 receives temporary credentials instead of a stored access key."
echo "On AWS the instance fetches them from the metadata service and they are renewed for it."
echo "Here they are requested by hand to show what they look like:"
read -r t_id t_secret t_token t_expires < <(aws sts assume-role \
  --role-arn "arn:aws:iam::$ACCOUNT:role/Ec2MonitorRole" --role-session-name web-1 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]' --output text)
echo "  AccessKeyId:  ${t_id:0:8}...   (starts with ASIA: temporary; a user's key starts with AKIA)"
echo "  SessionToken: ${#t_token} characters"
echo "  Expiration:   $t_expires"
export AWS_ACCESS_KEY_ID=$t_id AWS_SECRET_ACCESS_KEY=$t_secret AWS_SESSION_TOKEN=$t_token
echo "Acting with the temporary credentials:"
run aws sts get-caller-identity --query 'Arn' --output text
run aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --output text
echo "\$ aws ec2 terminate-instances --instance-ids $web2"
expect_denied aws ec2 terminate-instances --instance-ids "$web2"
unset AWS_SESSION_TOKEN

step "Done"
echo "The moto server keeps running on port 8200 with everything created above."
echo "Its state lives in memory: it is gone when the container is removed or this lab is run again."
echo "Next: setup/run.sh day-08/verify.sh"

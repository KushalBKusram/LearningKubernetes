#!/usr/bin/env bash
# Day 08 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./common.sh
need_docker

policy_arn="arn:aws:iam::$ACCOUNT:policy/Ec2MonitorAndRestart"
admin() { (use_user cli-admin && aws "$@"); }
monitor() { (use_user monitor-script && aws "$@"); }
text() { "$@" --output text 2>/dev/null; }

moto_up() { curl -s -o /dev/null -m 3 http://localhost:8200/moto-api/; }
rejects_unknown_key() {
  ! (export AWS_ACCESS_KEY_ID=AKIAUNKNOWNKEY000000 AWS_SECRET_ACCESS_KEY=wrong && unset AWS_SESSION_TOKEN && aws ec2 describe-regions)
}
admin_identity() { [ "$(text admin sts get-caller-identity --query Arn)" = "arn:aws:iam::$ACCOUNT:user/cli-admin" ]; }
three_zones() { [ "$(text admin ec2 describe-availability-zones --query 'length(AvailabilityZones)')" = "3" ]; }
two_instances() {
  [ "$(text admin ec2 describe-instances --filters 'Name=tag:Name,Values=web-1,web-2' --query 'length(Reservations[].Instances[])')" = "2" ]
}
no_inline_policy() { [ "$(text admin iam list-user-policies --user-name monitor-script --query 'length(PolicyNames)')" = "0" ]; }
managed_attached() {
  [ "$(text admin iam list-attached-user-policies --user-name monitor-script --query 'AttachedPolicies[].PolicyArn')" = "$policy_arn" ]
}
policy_shared() {
  [ "$(text admin iam list-entities-for-policy --policy-arn "$policy_arn" --query '[length(PolicyUsers),length(PolicyRoles)]' | tr -s '\t ' ' ')" = "2 1" ]
}
policy_names_instance() {
  local web1
  web1=$(admin ec2 describe-instances --filters 'Name=tag:Name,Values=web-1' --query 'Reservations[].Instances[].InstanceId' --output text)
  admin iam get-policy-version --policy-arn "$policy_arn" --version-id v1 --output json | grep -qF "instance/$web1"
}
monitor_can_read() { [ -n "$(text monitor ec2 describe-instances --query 'Reservations[].Instances[].InstanceId')" ]; }
monitor_cannot_terminate() {
  local web2
  web2=$(admin ec2 describe-instances --filters 'Name=tag:Name,Values=web-2' --query 'Reservations[].Instances[].InstanceId' --output text)
  local out
  out=$(monitor ec2 terminate-instances --instance-ids "$web2" 2>&1)
  [[ $out == *AccessDenied* ]]
}
monitor_cannot_use_iam() {
  local out
  out=$(monitor iam list-users 2>&1)
  [[ $out == *AccessDenied* ]]
}
bucket_allowed() { [ "$(monitor s3 cp s3://day08-reports/status.txt - 2>/dev/null)" = "all systems normal" ]; }
bucket_denied() { ! monitor s3 cp s3://day08-private/status.txt -; }
role_trusts_ec2() {
  [ "$(text admin iam get-role --role-name Ec2MonitorRole --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service')" = "ec2.amazonaws.com" ]
}
profile_on_web1() {
  [ "$(text admin ec2 describe-iam-instance-profile-associations --query 'IamInstanceProfileAssociations[0].IamInstanceProfile.Arn')" = "arn:aws:iam::$ACCOUNT:instance-profile/Ec2MonitorRole" ]
}
temporary_credentials_work() {
  local id secret token
  read -r id secret token < <(admin sts assume-role --role-arn "arn:aws:iam::$ACCOUNT:role/Ec2MonitorRole" \
    --role-session-name verify --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
  [ "${id:0:4}" = "ASIA" ] || return 1
  (export AWS_ACCESS_KEY_ID=$id AWS_SECRET_ACCESS_KEY=$secret AWS_SESSION_TOKEN=$token &&
    [[ $(aws sts get-caller-identity --query Arn --output text) == *assumed-role/Ec2MonitorRole/verify ]])
}

step "Day 08 verification"
echo "the account stand-in"
check "the moto server answers on port 8200" moto_up
check "an unknown access key is rejected" rejects_unknown_key
check "cli-admin's access key identifies as user/cli-admin" admin_identity
check "region eu-west-3 has three availability zones" three_zones
check "instances web-1 and web-2 exist" two_instances
echo "the restricted user"
check "monitor-script can read EC2 (ec2:Describe*)" monitor_can_read
check "monitor-script cannot terminate an instance" monitor_cannot_terminate
check "monitor-script cannot use IAM" monitor_cannot_use_iam
check "monitor-script can read the bucket named in its policy" bucket_allowed
check "monitor-script cannot read another bucket" bucket_denied
echo "managed policy"
check "monitor-script has no inline policy left" no_inline_policy
check "the managed policy Ec2MonitorAndRestart is attached to monitor-script" managed_attached
check "the managed policy is shared by two users and one role" policy_shared
check "the managed policy names instance web-1 by its ARN" policy_names_instance
echo "role"
check "role Ec2MonitorRole trusts the EC2 service" role_trusts_ec2
check "its instance profile is associated with an instance" profile_on_web1
check "the role hands out temporary credentials (ASIA...) that work" temporary_credentials_work
summary

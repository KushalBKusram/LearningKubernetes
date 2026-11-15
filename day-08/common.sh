#!/usr/bin/env bash
# Shared by lab.sh, verify.sh and aws-as.sh. Source it from the day-08 folder.

work=$PWD/.work
ACCOUNT=123456789012 # the fixed account id of the moto server
export AWS_DEFAULT_REGION=eu-west-3 # Paris, the region in the slides' ARN example

# The real AWS CLI, run from its container image and pointed at the moto server
# instead of AWS. Credentials come from the three AWS_* environment variables of
# the calling shell, as on slide 188.
aws() {
  docker run --rm --network day08-net \
    -v "$PWD:/lab:ro" -w /lab \
    -e AWS_ENDPOINT_URL=http://day08-moto:5000 \
    -e AWS_DEFAULT_REGION -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
    -e AWS_PAGER= \
    amazon/aws-cli "$@"
}

# use_user <name>: switch to the access key stored for that user.
use_user() {
  if [ ! -f "$work/$1.env" ]; then
    echo "No stored access key for '$1'. Run day-08/lab.sh first." >&2
    return 1
  fi
  unset AWS_SESSION_TOKEN
  set -a
  . "$work/$1.env"
  set +a
}

# create_key <name>: create an access key for a user and store it in .work/<name>.env.
create_key() {
  local id secret
  read -r id secret < <(aws iam create-access-key --user-name "$1" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  (umask 077 && printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' "$id" "$secret" >"$work/$1.env")
  echo "Access key for $1: ${id:0:8}... (stored in day-08/.work/$1.env; it only works against this moto server)"
}

# instance_id <Name tag>
instance_id() {
  aws ec2 describe-instances --filters "Name=tag:Name,Values=$1" \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

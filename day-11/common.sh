#!/usr/bin/env bash
# Shared by lab.sh and verify.sh. Source it from the day-11 folder.

VPC_CIDR=10.211.0.0/16
PUBLIC_CIDR=10.211.1.0/24
PRIVATE_CIDR=10.211.2.0/24
export AWS_DEFAULT_REGION=eu-west-3

# The real AWS CLI from its container image, pointed at the moto server that day 8
# started (container day08-moto). The access key is the one day 8 stored for cli-admin.
aws() {
  docker run --rm --network day08-net \
    -e AWS_ENDPOINT_URL=http://day08-moto:5000 \
    -e AWS_DEFAULT_REGION -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_PAGER= \
    amazon/aws-cli "$@"
}

# Load day 8's access key for cli-admin. Returns 1 with a hint when day 8 has not been run.
use_admin() {
  local env=../day-08/.work/cli-admin.env
  if [ ! -f "$env" ] || ! docker container inspect day08-moto >/dev/null 2>&1; then
    echo "The AWS half of this day uses the moto server from day 8. Run day-08/lab.sh first." >&2
    return 1
  fi
  set -a
  . "$env"
  set +a
}

# Can container $1 open a TCP connection to $2:$3 within 3 seconds?
can_connect() {
  docker exec "$1" timeout 3 bash -c "echo > /dev/tcp/$2/$3" >/dev/null 2>&1
}

# Address of container $1 on network $2.
ip_on() {
  docker container inspect -f "{{(index .NetworkSettings.Networks \"$2\").IPAddress}}" "$1"
}

# Id of the VPC named day11-vpc in moto, if there is one.
vpc_id() {
  aws ec2 describe-vpcs --filters Name=tag:Name,Values=day11-vpc \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -v '^None$'
}

# Remove everything day 11 created in moto, dependents first.
teardown_vpc() {
  local vpc id assoc
  vpc=$(vpc_id) || return 0
  for id in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" Name=tag:Name,Values=day11-* \
    --query 'RouteTables[].RouteTableId' --output text); do
    for assoc in $(aws ec2 describe-route-tables --route-table-ids "$id" \
      --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text); do
      aws ec2 disassociate-route-table --association-id "$assoc"
    done
  done
  for id in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" Name=tag:Name,Values=day11-* \
    --query 'RouteTables[].RouteTableId' --output text); do
    aws ec2 delete-route-table --route-table-id "$id"
  done
  for id in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" \
    --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$id" --vpc-id "$vpc"
    aws ec2 delete-internet-gateway --internet-gateway-id "$id"
  done
  for id in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --subnet-id "$id"
  done
  for id in $(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$vpc" Name=default,Values=false \
    --query 'NetworkAcls[].NetworkAclId' --output text); do
    aws ec2 delete-network-acl --network-acl-id "$id"
  done
  # sg-db refers to sg-web, so it has to go first.
  for name in day11-db day11-web; do
    for id in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" "Name=group-name,Values=$name" \
      --query 'SecurityGroups[].GroupId' --output text); do
      aws ec2 delete-security-group --group-id "$id"
    done
  done
  aws ec2 delete-vpc --vpc-id "$vpc"
}

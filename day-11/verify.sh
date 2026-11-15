#!/usr/bin/env bash
# Day 11 checks. Run after lab.sh.
set -uo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./common.sh
need_docker
use_admin || exit 1

running() { [ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
net_prop() { docker network inspect -f "$2" "$1"; }
public_subnet() { [ "$(net_prop day11-public '{{(index .IPAM.Config 0).Subnet}} {{.Internal}}')" = "$PUBLIC_CIDR false" ]; }
private_subnet() { [ "$(net_prop day11-private '{{(index .IPAM.Config 0).Subnet}} {{.Internal}}')" = "$PRIVATE_CIDR true" ]; }
web_in_both() { [ "$(docker container inspect -f '{{range $n, $_ := .NetworkSettings.Networks}}{{$n}} {{end}}' day11-web | tr ' ' '\n' | grep -c '^day11-')" = "2" ]; }
db_private_only() { [ "$(docker container inspect -f '{{range $n, $_ := .NetworkSettings.Networks}}{{$n}}{{end}}' day11-db)" = "day11-private" ]; }
outsider_public_only() { [ "$(docker container inspect -f '{{range $n, $_ := .NetworkSettings.Networks}}{{$n}}{{end}}' day11-outsider)" = "day11-public" ]; }
web_page() { curl -s -m 3 http://localhost:8211 | grep -qF 'Day 11: the web tier'; }
db_not_published() { [ -z "$(docker port day11-db)" ]; }
db_port_closed_on_host() { ! (echo >/dev/tcp/127.0.0.1/3306) 2>/dev/null; }
web_to_db() { can_connect day11-web day11-db 3306; }
outsider_to_db_name() { ! can_connect day11-outsider day11-db 3306; }
outsider_to_db_ip() { ! can_connect day11-outsider "$(ip_on day11-db day11-private)" 3306; }
web_to_internet() { can_connect day11-web 1.1.1.1 443; }
db_to_internet() { ! can_connect day11-db 1.1.1.1 443; }

vpc_cidr() { [ "$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=day11-vpc --query 'Vpcs[0].CidrBlock' --output text)" = "$VPC_CIDR" ]; }
two_zones() {
  local q=(ec2 describe-subnets --filters Name=tag:Name,Values=day11-public,day11-private)
  [ "$(aws "${q[@]}" --query 'length(Subnets)' --output text)" = "2" ] &&
    [ "$(aws "${q[@]}" --query 'Subnets[0].AvailabilityZone != Subnets[1].AvailabilityZone' --output text)" = "True" ]
}
igw_attached() {
  [ "$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=day11-igw" \
    --query 'InternetGateways[0].Attachments[0].VpcId' --output text)" = "$(vpc_id)" ]
}
default_routes() { # <route table name> -> number of 0.0.0.0/0 routes
  aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$1" \
    --query 'length(RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`])' --output text
}
public_route() { [ "$(default_routes day11-public-rt)" = "1" ]; }
private_no_route() { [ "$(default_routes day11-private-rt)" = "0" ]; }
sg_db_source() {
  local web db
  web=$(aws ec2 describe-security-groups --filters Name=group-name,Values=day11-web --query 'SecurityGroups[0].GroupId' --output text)
  db=$(aws ec2 describe-security-groups --filters Name=group-name,Values=day11-db --query 'SecurityGroups[0].GroupId' --output text)
  [ "$(aws ec2 describe-security-groups --group-ids "$db" \
    --query 'SecurityGroups[0].IpPermissions[0].UserIdGroupPairs[0].GroupId' --output text)" = "$web" ]
}
sg_web_open() {
  [ "$(aws ec2 describe-security-groups --filters Name=group-name,Values=day11-web \
    --query 'SecurityGroups[0].IpPermissions[0].IpRanges[0].CidrIp' --output text)" = "0.0.0.0/0" ]
}
acl_stateless() {
  local acl
  acl=$(aws ec2 describe-network-acls --filters Name=tag:Name,Values=day11-public-acl --query 'NetworkAcls[0].NetworkAclId' --output text)
  [ "$(aws ec2 describe-network-acls --network-acl-ids "$acl" \
    --query 'length(NetworkAcls[0].Entries[?RuleNumber==`100`])' --output text)" = "2" ]
}

step "Day 11 verification"
echo "the Docker layout"
check "day11-public is a normal network, 10.211.1.0/24" public_subnet
check "day11-private is an internal network, 10.211.2.0/24" private_subnet
check "web, db and outsider are running" bash -c "$(declare -f running); running day11-web && running day11-db && running day11-outsider"
check "web is in both subnets" web_in_both
check "db is in the private subnet only" db_private_only
check "outsider is in the public subnet only" outsider_public_only
echo "who can reach whom"
check "web page answers on port 8211" web_page
check "the database publishes no port" db_not_published
check "port 3306 is closed on the server" db_port_closed_on_host
check "web can reach the database by name" web_to_db
check "outsider cannot reach the database by name" outsider_to_db_name
check "outsider cannot reach the database by address" outsider_to_db_ip
check "web (public subnet) can reach the internet" web_to_internet
check "db (private subnet) cannot reach the internet" db_to_internet
echo "the same layout in AWS terms (moto)"
check "VPC day11-vpc exists with 10.211.0.0/16" vpc_cidr
check "the two subnets are in different availability zones" two_zones
check "the Internet Gateway is attached to the VPC" igw_attached
check "the public route table sends 0.0.0.0/0 to the gateway" public_route
check "the private route table has no default route" private_no_route
check "security group day11-web allows port 80 from anywhere" sg_web_open
check "security group day11-db allows 3306 only from the web group" sg_db_source
check "the network ACL has a rule 100 in each direction" acl_stateless
summary

#!/usr/bin/env bash
# Day 11 lab: networking in AWS (slides 232-247), without an AWS account.
#
# Part 1 builds the slides' layout out of Docker networks and proves who can reach whom.
# Part 2 builds the same layout with the real AWS CLI against the moto server from day 8.
#
# Needs day 8 first (the moto server). Safe to run more than once.
set -euo pipefail
cd "$(dirname "$0")"
. ../setup/lib.sh
. ./common.sh
need_docker

# Print one row of the reachability table. $4 is what AWS-style rules would give.
row() {
  local from=$1 to=$2 expected=$3 result=$4
  local mark="ok"
  [ "$result" = "$expected" ] || mark="UNEXPECTED"
  printf '  %-32s %-27s %-9s %s\n' "$from" "$to" "$result" "$mark"
}
try() { # try <container> <host> <port> -> connects / blocked
  if can_connect "$1" "$2" "$3"; then echo connects; else echo blocked; fi
}

step "1. Start clean (only day 11's own containers and networks)"
docker rm -f day11-web day11-db day11-outsider >/dev/null 2>&1 || true
docker network rm day11-public day11-private >/dev/null 2>&1 || true

step "2. Two subnets (slides 236, 239)"
echo "Public subnet: an ordinary Docker network. It has a gateway, so its containers can reach the internet,"
echo "and a container in it can publish a port."
run docker network create --subnet "$PUBLIC_CIDR" day11-public
echo
echo "Private subnet: a Docker network created with --internal. It has no route out and nothing can be published from it."
run docker network create --internal --subnet "$PRIVATE_CIDR" day11-private
echo
docker network inspect day11-public day11-private \
  --format '  {{.Name}}: subnet {{(index .IPAM.Config 0).Subnet}}  gateway {{(index .IPAM.Config 0).Gateway}}  internal={{.Internal}}'

step "3. Three machines (slide 234: resources in a VPC talk to each other directly)"
echo "web: in both subnets, the only one reachable from outside. db: in the private subnet only."
echo "outsider: a machine in the public subnet only, to test what the private subnet protects."
run docker run -d --restart unless-stopped --name day11-db --network day11-private \
  -e MARIADB_ROOT_PASSWORD=day11-not-a-secret -e MARIADB_DATABASE=app mariadb
run docker run -d --restart unless-stopped --name day11-web --network day11-public -p 8211:80 \
  -v "$PWD/web:/usr/share/nginx/html:ro" nginx
run docker network connect day11-private day11-web
run docker run -d --restart unless-stopped --name day11-outsider --network day11-public ubuntu sleep infinity
echo
echo "Waiting for the database to accept connections..."
for _ in $(seq 1 60); do
  can_connect day11-web day11-db 3306 && break
  sleep 1
done
web_pub=$(ip_on day11-web day11-public)
web_priv=$(ip_on day11-web day11-private)
db_ip=$(ip_on day11-db day11-private)
echo "web:      $web_pub (public subnet)  and  $web_priv (private subnet)"
echo "db:       $db_ip (private subnet)"
echo "outsider: $(ip_on day11-outsider day11-public) (public subnet)"

step "4. Who can reach whom (slide 247)"
printf '  %-32s %-27s %-9s %s\n' FROM TO RESULT 'AS EXPECTED?'
echo "  $(printf '%.0s-' $(seq 1 78))"
row "the server (outside the VPC)" "web, port 8211" connects \
  "$(curl -s -o /dev/null -m 3 http://localhost:8211 && echo connects || echo blocked)"
row "the server (outside the VPC)" "db, port 3306" blocked \
  "$( (echo >/dev/tcp/127.0.0.1/3306) 2>/dev/null && echo connects || echo blocked)"
row "web (public + private)" "db by name, 3306" connects "$(try day11-web day11-db 3306)"
row "outsider (public only)" "db by name, 3306" blocked "$(try day11-outsider day11-db 3306)"
row "outsider (public only)" "db by address, 3306" blocked "$(try day11-outsider "$db_ip" 3306)"
row "web (public subnet)" "the internet, 1.1.1.1:443" connects "$(try day11-web 1.1.1.1 443)"
row "db (private subnet)" "the internet, 1.1.1.1:443" blocked "$(try day11-db 1.1.1.1 443)"
echo
echo "Published ports of web: $(docker port day11-web | tr '\n' ' ')"
echo "Published ports of db:  '$(docker port day11-db | tr '\n' ' ')' (none)"

step "5. Finding the broken condition, as the slide 247 checklist suggests"
echo "The outsider cannot reach the database. 'Route to host' is the missing condition: it shares no network with it."
echo "Give it a route by putting it into the private subnet:"
run docker network connect day11-private day11-outsider
echo "outsider -> db:3306 now: $(try day11-outsider day11-db 3306)"
echo "Take the route away again:"
run docker network disconnect day11-private day11-outsider
echo "outsider -> db:3306 now: $(try day11-outsider day11-db 3306)"
echo
echo "AWS would only report that the connection failed. The same walk applies there: route, network ACL, security groups."

step "6. The same layout in AWS terms (slides 234-245), against the moto server from day 8"
use_admin
echo "Docker network       ->  AWS"
echo "  both networks      ->  the VPC, $VPC_CIDR"
echo "  day11-public       ->  public subnet $PUBLIC_CIDR (route to an Internet Gateway)"
echo "  day11-private      ->  private subnet $PRIVATE_CIDR (no such route)"
echo "  published port 80  ->  security group day11-web: inbound 80 from anywhere"
echo "  db reachable by web only -> security group day11-db: inbound 3306 from security group day11-web"
echo
echo "Removing the objects of an earlier run:"
teardown_vpc || true

vpc=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=day11-vpc}]' --query 'Vpc.VpcId' --output text)
echo "VPC $vpc ($VPC_CIDR)"

pub_subnet=$(aws ec2 create-subnet --vpc-id "$vpc" --cidr-block "$PUBLIC_CIDR" --availability-zone eu-west-3a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=day11-public}]' --query 'Subnet.SubnetId' --output text)
priv_subnet=$(aws ec2 create-subnet --vpc-id "$vpc" --cidr-block "$PRIVATE_CIDR" --availability-zone eu-west-3b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=day11-private}]' --query 'Subnet.SubnetId' --output text)
echo "Each subnet lives in exactly one availability zone (slide 236):"
aws ec2 describe-subnets --subnet-ids "$pub_subnet" "$priv_subnet" \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,SubnetId,CidrBlock,AvailabilityZone]' --output table

echo
echo "Public versus private is decided by the route table (slide 239):"
igw=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=day11-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc"
pub_rt=$(aws ec2 create-route-table --vpc-id "$vpc" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=day11-public-rt}]' \
  --query 'RouteTable.RouteTableId' --output text)
priv_rt=$(aws ec2 create-route-table --vpc-id "$vpc" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=day11-private-rt}]' \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$pub_rt" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw" >/dev/null
aws ec2 associate-route-table --route-table-id "$pub_rt" --subnet-id "$pub_subnet" >/dev/null
aws ec2 associate-route-table --route-table-id "$priv_rt" --subnet-id "$priv_subnet" >/dev/null
for rt in day11-public-rt day11-private-rt; do
  echo "  $rt:"
  aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$rt" \
    --query 'RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId]' --output text | sed 's/^/    /'
done
echo "  The public subnet has a route to the Internet Gateway ($igw); the private one only has the local route."

echo
echo "Network ACL: a stateless firewall on the subnet (slide 243). Allowing traffic in does not allow the answer out:"
nacl=$(aws ec2 create-network-acl --vpc-id "$vpc" \
  --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=day11-public-acl}]' \
  --query 'NetworkAcl.NetworkAclId' --output text)
aws ec2 create-network-acl-entry --network-acl-id "$nacl" --rule-number 100 --protocol tcp --port-range From=80,To=80 \
  --cidr-block 0.0.0.0/0 --rule-action allow --ingress
aws ec2 create-network-acl-entry --network-acl-id "$nacl" --rule-number 100 --protocol tcp --port-range From=1024,To=65535 \
  --cidr-block 0.0.0.0/0 --rule-action allow --egress
aws ec2 describe-network-acls --network-acl-ids "$nacl" \
  --query 'NetworkAcls[0].Entries[?RuleNumber==`100`].[Egress,RuleAction,Protocol,PortRange.From,PortRange.To]' --output text |
  sed 's/^True/  outbound:/; s/^False/  inbound: /; s/\t/ /g' | sed 's/ 6 / tcp /'
echo "  inbound lets port 80 in; outbound has to let the answer (ports 1024-65535) back out."

echo
echo "Security groups: stateful firewalls on the instance (slide 245):"
sg_web=$(aws ec2 create-security-group --group-name day11-web --description "web tier" --vpc-id "$vpc" \
  --query GroupId --output text)
sg_db=$(aws ec2 create-security-group --group-name day11-db --description "database tier" --vpc-id "$vpc" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$sg_web" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$sg_db" --protocol tcp --port 3306 --source-group "$sg_web" >/dev/null
for g in "$sg_web" "$sg_db"; do
  aws ec2 describe-security-groups --group-ids "$g" \
    --query 'SecurityGroups[0].[GroupName,IpPermissions[0].FromPort,IpPermissions[0].IpRanges[0].CidrIp,IpPermissions[0].UserIdGroupPairs[0].GroupId]' \
    --output text | awk '{ src = ($3 != "None") ? $3 : "members of " $4; printf "  %s: inbound port %s from %s\n", $1, $2, src }'
done
echo "  The database accepts connections only from members of the web security group, not from any address range."

echo
echo "moto stores all of this and returns it, but it does not route packets or enforce these rules."

step "Done"
echo "Left running: day11-web on port 8211, day11-db and day11-outsider (no published ports)."
echo "The AWS objects are in the day 8 moto server."
echo "Next: setup/run.sh day-11/verify.sh"

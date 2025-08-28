_vpc_id() {
  cidr_block=$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')
  aws ec2 describe-vpcs |
    jq --arg cidr "$cidr_block" -r '.Vpcs[] | select(.CidrBlock == $cidr) | .VpcId' |
    grep -v 'null' | cat
}

_vpc_subnet_from_cidr_block() {
  local cidr_block
  cidr_block="$1"
  aws ec2 describe-subnets |
  jq --arg vpc_id "$(_vpc_id)" --arg cidr "$subnet_cidr_block" \
    '.Subnets[] | select(.VpcId == $vpc_id and .CidrBlock == $cidr) | .SubnetId' |
  grep -v null |
  cat
}

_vpc_subnet_from_availability_zone() {
  local az
  az="$1"
  az_id="$(aws ec2 describe-availability-zones |
    jq --arg name "$az" -r '.AvailabilityZones[] | select(.ZoneName == $name) | .ZoneId' |
    grep -v null | cat)"
  aws ec2 describe-subnets |
    jq -r --arg vpc_id "$(_vpc_id)" --arg az_id "$az_id" \
      '.Subnets[] | select(.VpcId == $vpc_id and .AvailabilityZoneId == $az_id) | .SubnetId' |
      grep -v null | cat
}


_all_availability_zones() {
  local az
  az=""
  for t in bootstrap control_plane workers
  do az="${az}$(_get_from_config ".deploy.cloud_config.aws.networking.availability_zones.${t}[]")\n"
  done
  echo -e "$az" | grep -Ev '^$' | sort -u
}

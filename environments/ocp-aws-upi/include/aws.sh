# shellcheck shell=bash
_this_ip() {
  curl -sSL api.ipify.org
}

_bootstrap_subnet() {
  bootstrap_az=$(_get_from_config '.deploy.cloud_config.aws.networking.availability_zones.bootstrap[0]')
  public_subnets=$(fail_if_nil "$(_get_param_from_aws_cfn_stack vpc 'PublicSubnetIds')" \
    "Public subnets not found" | tr ',' ' ')
  _exec_aws ec2 describe-subnets --subnet-ids $public_subnets |
    jq -r --arg az "$bootstrap_az" '.Subnets[] | select(.AvailabilityZone == $az) | .SubnetId'
}

_hosted_zone_id() {
  domain_name=$(_get_from_config '.deploy.cloud_config.aws.networking.dns.domain_name')
  _exec_aws route53 list-hosted-zones |
    jq --arg name "$domain_name" -r '.HostedZones[] | select(.Name == $name + ".") | .Id' |
    grep -v null |
    cat
}

_hosted_zone_name() {
  domain_name=$(_get_from_config '.deploy.cloud_config.aws.networking.dns.domain_name')
  _exec_aws route53 list-hosted-zones |
    jq --arg name "$domain_name" -r '.HostedZones[] | select(.Name == $name + ".") | .Name' |
    grep -v null |
    sed -E 's/\.$//' | cat
}

_all_availability_zones() {
  local az
  az=""
  for t in bootstrap control_plane workers
  do az="${az}$(_get_from_config ".deploy.cloud_config.aws.networking.availability_zones.${t}[]")\n"
  done
  echo -e "$az" | grep -Ev '^$' | sort -u
}

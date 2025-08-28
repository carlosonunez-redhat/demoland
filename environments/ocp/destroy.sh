#!/usr/bin/env bash
set -e
source "$(dirname "$0")/../include/helpers/aws.sh"
source "$(dirname "$0")/../include/helpers/config.sh"
source "$(dirname "$0")/../include/helpers/data.sh"
source "$(dirname "$0")/../include/helpers/logging.sh"
source "$(dirname "$0")/include/aws.sh"
source "$(dirname "$0")/include/ocp.sh"

delete_aws_ec2_key_pair() {
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  test -z "$(aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  info "Deleting EC2 key pair '$key_name'"
  aws ec2 delete-key-pair --key-name "$key_name"
}

delete_ssh_key() {
  info "Deleting SSH key"
  rm -f "$(_get_files_from_data_dir 'id_rsa*')"
}

delete_ec2_subnets() {
  cidr_block=$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')
  vpc_id="$(aws ec2 describe-vpcs |
    jq --arg cidr "$cidr_block" -r '.Vpcs[] | select(.CidrBlock == $cidr) | .VpcId' |
    grep -v 'null' | cat)"
  for az in $(_all_availability_zones)
  do
    subnet_id="$(_vpc_subnet_from_availability_zone "$az")"
    test -z "$subnet_id" && continue
    info "Deleting subnet $subnet_id in VPC $vpc_id"
    aws ec2 delete-subnet --subnet-id "$subnet_id" || return 1
    idx=$((idx+1))
  done
}

delete_ec2_vpc() {
  vpc_id="$(_vpc_id)"
  test -z "$vpc_id" && return 0
  info "Deleting AWS VPC '$vpc_id'"
  aws ec2 delete-vpc --vpc-id "$vpc_id"
}

detach_vpc_internet_gateway() {
  id="$(aws resourcegroupstaggingapi get-resources --tag-filters "Key=name,Values=ocp-aws-igw" |
    jq -r '.ResourceTagMappingList[0].ResourceARN' |
    grep -v null |
    awk -F'/' '{print $NF}' |
    cat)"
  test -z "$(aws ec2 describe-internet-gateways --internet-gateway-id "$id" |
    jq --arg id "$(_vpc_id)" \
      -r '.InternetGateways[].Attachments[] | select(.VpcId == $id) | .VpcId' |
    grep -v null | cat)" && return 0
  info "Detaching Internet Gateway '$id' to VPC '$(_vpc_id)'"
  aws ec2 detach-internet-gateway --internet-gateway-id "$id" --vpc-id "$(_vpc_id)"
}

delete_vpc_internet_gateway() {
  id="$(aws resourcegroupstaggingapi get-resources --tag-filters "Key=name,Values=ocp-aws-igw" |
    jq -r '.ResourceTagMappingList[0].ResourceARN' |
    grep -v null |
    awk -F'/' '{print $NF}' |
    cat)"
  test -z "$id" && return 0
  info "Deleting internet gateway $id"
  aws ec2 delete-internet-gateway --internet-gateway-id "$id"
}

export $(log_into_aws) || exit 1
delete_aws_ec2_key_pair
delete_ssh_key
detach_vpc_internet_gateway
delete_vpc_internet_gateway
delete_ec2_subnets
delete_ec2_vpc

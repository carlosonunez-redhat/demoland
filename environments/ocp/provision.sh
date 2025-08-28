#!/usr/bin/env bash
set -e
source "$(dirname "$0")/../include/helpers/aws.sh"
source "$(dirname "$0")/../include/helpers/config.sh"
source "$(dirname "$0")/../include/helpers/data.sh"
source "$(dirname "$0")/../include/helpers/logging.sh"
source "$(dirname "$0")/include/aws.sh"
source "$(dirname "$0")/include/ocp.sh"

create_ssh_key() {
  f="$(_get_file_from_data_dir 'id_rsa')"
  test -f "$f" && test "$(stat -c %a "$f")" -eq 600 && return 0

  info "Creating an SSH key for the nodes"
  _get_from_config 'deploy.secrets.ssh_key.data' > "$f"
  chmod 600 "$f"
}

load_keys_into_ssh_agent() {
  info "Starting SSH agent and loading keys"
  eval "$(ssh-agent -s)" &>/dev/null
  >&2 ssh-add -q "$(_get_file_from_data_dir 'id_rsa')"
}

upload_key_into_ec2() {
  info "Creating AWS EC2 key pair from SSH private key"
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  test -n "$(aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  pubkey="$(ssh-keygen -yf "$(_get_file_from_data_dir 'id_rsa')")"
  >/dev/null aws ec2 import-key-pair --key-name "$key_name" \
    --public-key-material "$(base64 -w 0 <<< "$pubkey")"
}

create_ec2_vpc() {
  test -n "$(_vpc_id)" && return 0
  cidr_block=$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')
  info "Creating AWS VPC with CIDR '$cidr_block'"
  aws ec2 create-vpc --cidr-block "$cidr_block"
}

create_ec2_subnets() {
  idx=0
  for az in $(_all_availability_zones)
  do
    subnet_cidr_block="$(cut -f1-2 -d '.' <<< "$cidr_block").$idx.0/24"
    test -n "$(_vpc_subnet_from_cidr_block "$subnet_cidr_block")" && continue
    info "Creating subnet $subnet_cidr_block in VPC $(_vpc_id) and AZ $az"
    aws ec2 create-subnet --vpc-id "$(_vpc_id)" \
      --cidr-block "$subnet_cidr_block" \
      --availability-zone "$az" >/dev/null || return 1
    idx=$((idx+1))
  done
}

create_bootstrap_instance() {
  ami=$(_rhcos_ami_id)
  vpc_id="$(aws ec2 describe-vpcs |
    jq --arg cidr "$cidr_block" -r '.Vpcs[] | select(.CidrBlock == $cidr) | .VpcId' |
    grep -v 'null' | cat)"
  if test -z "$ami"
  then
    error "Couldn't find an RHCOS AMI in $AWS_DEFAULT_REGION."
    return 1
  fi

  debug "AMI: $ami"
}

export $(log_into_aws) || exit 1
create_ssh_key
load_keys_into_ssh_agent
upload_key_into_ec2
create_ec2_vpc
create_ec2_subnets
create_bootstrap_instance

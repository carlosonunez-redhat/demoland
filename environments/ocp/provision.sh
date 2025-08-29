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

create_vpc() {
  local subnet_size subnet_bits params params_json
	subnet_size=$(_get_from_config '.deploy.cloud_config.aws.networking.subnet_size')
	test -z "$subnet_size" && subnet_size=24
	subnet_bits=$((32-subnet_size))
  params=(
    'VpcCidr' "$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')"
    'AvailabilityZoneCount' "$(_all_availability_zones | wc -l)"
    'SubnetBits' "$subnet_bits"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
  _create_aws_resources_from_cfn_stack 'vpc' "$params_json" "Creating VPC..."
}

export $(log_into_aws) || exit 1
create_ssh_key
load_keys_into_ssh_agent
upload_key_into_ec2
create_vpc

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
  aws ec2 delete-key-pair --key-name "$key_name" >/dev/null
}

delete_ssh_key() {
  info "Deleting SSH key"
  rm -f "$(_get_files_from_data_dir 'id_rsa*')"
}

delete_aws_vpc() {
  _delete_aws_resources_from_cfn_stack 'vpc' "Deleting VPC..."
}

delete_networking_resources() {
  _delete_aws_resources_from_cfn_stack networking \
    "Deleting DNS records, load balancers and target groups..."
}


export $(log_into_aws) || exit 1
delete_aws_ec2_key_pair
delete_ssh_key
delete_networking_resources
delete_aws_vpc

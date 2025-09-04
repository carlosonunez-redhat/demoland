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

delete_bootstrap_machine() {
  _delete_aws_resources_from_cfn_stack bootstrap_machine \
    "Deleting the bootstrap machine..."
}

delete_security_groups() {
  _delete_aws_resources_from_cfn_stack security \
    "Deleting security groups..."
}

delete_ignition_files() {
  rm -rf /data/ignition
}

delete_ignition_bucket_from_s3() {
  test -z "$(2>/dev/null aws s3api head-bucket \
    --bucket "$(_get_from_config '.deploy.node_config.common.ignition_file_s3_bucket')")" &&
    return 0

  info "Deleting S3 bucket for ignition files..."
  aws s3 rm --recursive "s3://$(_get_from_config '.deploy.node_config.common.ignition_file_s3_bucket')" &&
    aws s3 rb "s3://$(_get_from_config '.deploy.node_config.common.ignition_file_s3_bucket')"
}

delete_cluster_iam_user() {
  _delete_aws_resources_from_cfn_stack cluster_user "Deleting cluster user..."
}



export $(log_into_aws) || exit 1
delete_bootstrap_machine
delete_aws_ec2_key_pair
delete_security_groups
delete_ignition_bucket_from_s3
delete_networking_resources
delete_aws_vpc
delete_cluster_iam_user
delete_ssh_key
delete_ignition_files

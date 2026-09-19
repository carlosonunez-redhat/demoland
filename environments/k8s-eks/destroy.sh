#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/eks.sh"

delete_addons() {
  _delete_aws_resources_from_cfn_stack addons \
    "Deleting EKS add-ons..."
}

delete_worker_nodes() {
  _delete_aws_resources_from_cfn_stack worker_nodes \
    "Deleting worker nodes..."
}

delete_eks_cluster() {
  _delete_aws_resources_from_cfn_stack eks_cluster \
    "Deleting EKS cluster..."
}

delete_security_groups() {
  _delete_aws_resources_from_cfn_stack security \
    "Deleting security groups..."
}

delete_iam_roles() {
  _delete_aws_resources_from_cfn_stack iam \
    "Deleting IAM roles and instance profiles..."
}

delete_vpc() {
  _delete_aws_resources_from_cfn_stack vpc \
    "Deleting VPC..."
}

delete_ec2_key_pair() {
  local key_name
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  test -z "$(_exec_aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  info "Deleting EC2 key pair '$key_name'"
  _exec_aws ec2 delete-key-pair --key-name "$key_name" >/dev/null
}

delete_ssh_key() {
  info "Deleting SSH key from data directory"
  rm -f "$(_get_file_from_data_dir 'id_rsa')"
}

delete_kubeconfig() {
  info "Deleting EKS kubeconfig"
  rm -f "$(_eks_kubeconfig_path)"
}

delete_addons
delete_worker_nodes
delete_eks_cluster
delete_security_groups
delete_iam_roles
delete_vpc
delete_ec2_key_pair
delete_ssh_key
delete_kubeconfig

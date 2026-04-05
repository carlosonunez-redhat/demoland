#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
source "$ENVIRONMENT_INCLUDE_DIR/ocp.sh"

delete_aws_ec2_key_pair() {
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  test -z "$(_exec_aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  info "Deleting EC2 key pair '$key_name'"
  _exec_aws ec2 delete-key-pair --key-name "$key_name" >/dev/null
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
  test -z "$(2>/dev/null _exec_aws s3api head-bucket \
    --bucket "$(_cluster_ignition_files_bucket)")" &&
    return 0

  info "Deleting S3 bucket for ignition files..."
  _exec_aws s3 rm --recursive "s3://$(_cluster_ignition_files_bucket)" &&
    _exec_aws s3 rb "s3://$(_cluster_ignition_files_bucket)"
}

delete_cluster_iam_user() {
  _delete_aws_resources_from_cfn_stack cluster_user "Deleting cluster user..."
}

delete_cluster_iam_user_policy() {
  local infra_name policy_arns
  infra_name="$(_cluster_infra_name)"
  policy_name="${infra_name}-cluster_user-policy"
  policy_arns=$(_exec_aws iam list-policies |
    jq -r --arg name "$policy_name" '.Policies[] | select(.PolicyName | contains($name)) | .Arn'|
    grep -v null|
    cat)
  test -z "$policy_arns" && return 0

  for arn in $policy_arns
  do
    info "Deleting cluster user IAM policy $arn"
    _exec_aws iam delete-policy --policy-arn "$arn"
  done
}

delete_control_plane_machines() {
  _delete_aws_resources_from_cfn_stack control_plane_machines \
    "Deleting the control plane machines..."
}

delete_worker_machines() {
  _delete_aws_resources_from_cfn_stack worker_nodes \
    "Deleting the workers..."
}

delete_ingress_dns_records() {
  _delete_aws_resources_from_cfn_stack ingress \
    "Deleting ingress DNS records..."
}

delete_router_lbs() {
  _exec_aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/$(_cluster_infra_name),Values=owned" |
  jq -r '.ResourceTagMappingList[].ResourceARN' |
  while read -r arn
  do
    info "Deleting OpenShift router ELB resource [$arn]..."
    resource_name=$(echo "$arn" | awk -F '/' '{print $NF}')
    case "$arn" in
      *loadbalancer*)
        info "Deleting router load balancer [$resource_name]"
        _exec_aws elb delete-load-balancer --load-balancer-name "$resource_name"
        ;;
      *security-group*)
        info "Deleting router security group [$resource_name]"
        _exec_aws ec2 delete-security-group --group-id "$resource_name"
        ;;
      *)
        error "This resource has an unexpected type: $arn"
        continue
        ;;
    esac
  done
}


export $(log_into_aws) || exit 1
delete_ingress_dns_records
delete_worker_machines
delete_control_plane_machines
delete_ingress_dns_records
delete_router_lbs
delete_aws_ec2_key_pair
delete_security_groups
delete_ignition_bucket_from_s3
delete_networking_resources
delete_aws_vpc
delete_cluster_iam_user
delete_cluster_iam_user_policy
delete_ssh_key
delete_ignition_files

#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
source "$ENVIRONMENT_INCLUDE_DIR/ocp.sh"

_delete_sg_rules_wait_until_deleted() {
  local rules_deleted attempt max_attempts rules
  attempt=0
  max_attempts=60
  rules_deleted=false
  while test "$attempt" -lt "$max_attempts"
  do
    if test -z "$2"
    then rules=$(_exec_aws ec2 describe-security-groups --group-ids "$1" |
      jq -r '.SecurityGroups[].IpPermissions')
    else
      if test "$attempt" -eq 0 && test -n "$2"
      then rules="$2"
      # i'm not sure if the order of the keys in the IpPermissions object
      # are guaranteed. this won't work if they are.
      else rules=$(_exec_aws ec2 describe-security-groups --group-ids "$1" |
                   jq -cr '.SecurityGroups[].IpPermissions[]' |
                   grep -F "$2")
      fi
    fi
    num_rules=$(jq -r length <<< "$rules")
    test "$rules" == '[]' && break
    if test "$rules_deleted" == false
    then
      info "Deleting $num_rules rules for cluster-related sg [$1] (attempt $attempt of $max_attempts)..."
      _exec_aws ec2 revoke-security-group-ingress --group-id "$1" \
        --ip-permissions "$rules" &&
        rules_deleted=true
    else
      info "Waiting for $num_rules rule(s) for cluster-related sg [$1] to delete (attempt $attempt of $max_attempts)..."
      sleep 1
    fi
    attempt=$((attempt+1))
  done
}

_delete_sg_rule_containing_sg() {
    q="$(cat <<-EOF
.SecurityGroups[] |
   select(.IpPermissions[].UserIdGroupPairs[].GroupId | contains(\$SG_ID)) |
   {
     id: .GroupId,
     rule: ( (.IpPermissions[] |
               select(.UserIdGroupPairs != null) |
               select(.UserIdGroupPairs[].GroupId | contains(\$SG_ID)) ) )
   }
EOF
)"
  if ! sg_list=$(_exec_aws ec2 describe-security-groups | jq -cr --arg SG_ID "$1" -r "$q")
  then
    error "Failed to retrieve security groups dependent on '$1'"
    return 1
  fi
  for sg_info in $sg_list
  do
    set -x
    sg_id=$(jq -r '.id' <<< "$sg_info")
    sg_rule=$(jq -cr '.rule' <<< "$sg_info")
    _delete_sg_rules_wait_until_deleted "$sg_id" "[$sg_rule]"
    set +x
  done
}

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

delete_openshift_install_directory() {
  info "Deleting openshift-install directory '$(_openshift_install_dir)'"
  rm -rf "$(_openshift_install_dir)"
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

delete_router_resources() {
  _delete_with_wait() {
    attempts=0
    max_attempts=180
    terminated=false
    while test "$attempts" -lt "$max_attempts"
    do
      lb=$(_exec_aws elb describe-load-balancers --load-balancer-names "$1" || true)
      test -z "$lb" && return 0
      if test "$terminated" == false
      then
        info "Deleting load balancer [$1] (attempt $attempts of $max_attempts)"
        _exec_aws elb delete-load-balancer --load-balancer-name "$1"
      else
        info "Confirming that load balancer [$1] has been deleted \
(attempt $attempts of $max_attempts)"
      fi
      sleep 1
      attempts=$((attempts+1))
    done
  }
  _exec_aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/$(_cluster_infra_name),Values=owned" |
    jq -r '.ResourceTagMappingList[].ResourceARN' |
    sort -r |
    while read -r arn
    do
      info "Deleting OpenShift router ELB resource [$arn]..."
      resource_name=$(echo "$arn" | awk -F '/' '{print $NF}')
      case "$arn" in
        *loadbalancer*)
          info "Deleting router load balancer [$resource_name]"
          _delete_with_wait "$resource_name"
          ;;
        *security-group*)
          info "Deleting router security group [$resource_name]"
          _delete_sg_rule_containing_sg "$resource_name" &&
          _delete_sg_rules_wait_until_deleted "$resource_name" &&
          _exec_aws ec2 delete-security-group --group-id "$resource_name"
          ;;
        *)
          error "This resource has an unexpected type: $arn"
          continue
          ;;
      esac
    done
}

delete_extra_cluster_associated_machines() {
  _terminate_with_wait() {
    attempts=0
    max_attempts=180
    terminated=false
    while test "$attempts" -lt "$max_attempts"
    do
      state=$(_exec_aws ec2 describe-instances --instance-id "$1" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
      test "$state" == terminated && break

      if test "$terminated" == false
      then
        info "Deleting cluster-related node [$1] (attempt $attempts of $max_attempts)"
        _exec_aws ec2 terminate-instances --instance-id "$1" && terminated=true
      else
        info "Confirming that cluster-related node [$1] has been terminated \
(attempt $attempts of $max_attempts)"
      fi
      sleep 1
      attempts=$((attempts+1))
    done
  }
  _exec_aws ec2 describe-instances --filter "Name=tag:Name,Values=*$(_cluster_name)*" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text |
  while read -r instance
  do _terminate_with_wait "$instance" || return 1
  done
}

clear_extra_cluster_associated_sg_rules() {
  local cluster_sgs_json cf_sgs_json all_sgs_json rules
  cluster_sgs_json=$(_exec_aws ec2 describe-security-groups --filter "Name=tag:kubernetes.io/cluster/$(_cluster_infra_name),Values=owned" | jq -cr .)
  cf_sgs_json=$(_exec_aws ec2 describe-security-groups --filter "Name=tag:aws:cloudformation:stack-name,Values=$(_aws_cf_stack_name)*" | jq -cr .)
  all_sgs_json=$(echo "[$cluster_sgs_json,$cf_sgs_json]" | jq -cr flatten)
  jq -r '.[].SecurityGroups[].GroupId' <<< "$all_sgs_json" |
    while read -r sg
    do
      info "[$sg] Deleting rules..."
      _delete_sg_rules_wait_until_deleted "$sg" || return 1
    done
}

delete_extra_cluster_associated_sgs() {
  local cluster_sgs_json cf_sgs_json all_sgs_json rules
  cluster_sgs_json=$(_exec_aws ec2 describe-security-groups --filter "Name=tag:kubernetes.io/cluster/$(_cluster_infra_name),Values=owned" | jq -cr .)
  cf_sgs_json=$(_exec_aws ec2 describe-security-groups --filter "Name=tag:aws:cloudformation:stack-name,Values=$(_cluster_name)*" | jq -cr .)
  all_sgs_json=$(echo "[$cluster_sgs_json,$cf_sgs_json]" | jq -cr flatten)
  jq -r '.[].SecurityGroups[].GroupId' <<< "$all_sgs_json" |
    while read -r sg
    do
      info "[$sg] Deleting group..."
      _exec_aws ec2 delete-security-group --group-id "$sg"
    done
}


export $(log_into_aws) || exit 1
delete_worker_machines
delete_control_plane_machines
delete_bootstrap_machine
delete_router_resources
delete_extra_cluster_associated_machines
clear_extra_cluster_associated_sg_rules
delete_extra_cluster_associated_sgs
delete_ingress_dns_records
delete_aws_ec2_key_pair
delete_security_groups
delete_ignition_bucket_from_s3
delete_networking_resources
delete_aws_vpc
delete_cluster_iam_user
delete_cluster_iam_user_policy
delete_ssh_key
delete_openshift_install_directory

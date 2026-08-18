#!/usr/bin/env bash
# Provisions an environment!
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"

add_vm_network_nic() {
  instances=$(_exec_aws ec2 describe-instances \
    --query 'Reservations[].Instances[?(@.Tags[?Key==`Name` && contains(Value, `'"$(_cluster_infra_name)"'`)])]' | \
    jq -cr 'flatten | .[] | {
  id: .InstanceId,
  primary_nic: {
    subnet_id: .NetworkInterfaces[0].SubnetId,
    sg_id: .NetworkInterfaces[0].Groups[0].GroupId
  }
}')
  if test -z "$instances"
  then
    error "Couldn't find any nodes with cluster name: $(_cluster_infra_name)"
    return 1
  fi
  num_instances=$(jq -r '.[].id' <<< "$instances")
  if test "$num_instances" -gt 1
  then
    error "This function only supports single-node OpenShift clusters (found '$num_instances' nodes)"
    return 1
  fi
  params=(
    InstanceId "$(jq -r '.[0].id' <<< "$instances")"
    SubnetId "$(jq -r '.[0].primary_nic.subnet_id' <<< "$instances")"
    OCPControlPlaneSecurityGroupId "$(jq -r '.[0].primary_nic.sg_id' <<< "$instances")"
  )
  _create_aws_resources_from_cfn_stack_with_caps \
    vm_network \
    "$(_create_aws_cf_params_json "${params[@]}")" \
    "CAPABILITY_NAMED_IAM" \
    "Adding additional NIC for VM network..."
}

add_vm_network_nic

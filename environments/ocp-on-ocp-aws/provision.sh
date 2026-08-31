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
source "$ENVIRONMENT_INCLUDE_DIR/node.sh"
_vm_instance_data() {
  instances=$(_exec_aws ec2 describe-instances \
    --query 'Reservations[].Instances[?(@.State.Name == `running` && @.Tags[?Key==`Name` && contains(Value, `'"$(_cluster_infra_name)"'`)])]' | \
    jq -cr '[flatten | .[] | {
  id: .InstanceId,
  az: .Placement.AvailabilityZone,
  primary_nic: {
    subnet_id: .NetworkInterfaces[0].SubnetId,
    sg_id: .NetworkInterfaces[0].Groups[0].GroupId
  }
}]')
  if test -z "$instances"
  then
    error "Couldn't find any nodes with cluster name: $(_cluster_infra_name)"
    return 1
  fi
  num_instances=$(jq -r '[.[].id] | flatten | length' <<< "$instances")
  if test "$num_instances" -gt 1
  then
    error "This function only supports single-node OpenShift clusters (found '$num_instances' nodes)"
    return 1
  fi
  echo "$instances"
}

add_vm_network_nic() {
  params=(
    InstanceId "$(jq -r '.[0].id' <<< "$(_vm_instance_data)")"
    SubnetId "$(jq -r '.[0].primary_nic.subnet_id' <<< "$(_vm_instance_data)")"
    OCPControlPlaneSecurityGroupId "$(jq -r '.[0].primary_nic.sg_id' <<< "$(_vm_instance_data)")"
  )
  _create_aws_resources_from_cfn_stack_with_caps \
    vm_network \
    "$(_create_aws_cf_params_json "${params[@]}")" \
    "CAPABILITY_NAMED_IAM" \
    "Adding additional NIC for VM network..."
}

add_vm_storage_pool_disk() {
  params=(
    InstanceId "$(jq -r '.[0].id' <<< "$(_vm_instance_data)")"
    AZ "$(jq -r '.[0].az' <<< "$(_vm_instance_data)")"
  )
  _create_aws_resources_from_cfn_stack_with_caps \
    vm_storage \
    "$(_create_aws_cf_params_json "${params[@]}")" \
    "CAPABILITY_NAMED_IAM" \
    "Adding storage pool disk..."
}

format_vm_storage_pool_disk() {
  local want got
  want=ext4
  got=$(exec_on_virt_node_directly blkid -p "/dev/$(vm_storage_pool_disk_name)" -s TYPE -o value)
  test "$want" == "$got" && return 0

  info "Formatting VM storage pool disk '$(vm_storage_pool_disk_name)'"
  exec_on_virt_node parted -a optimal "/dev/$(vm_storage_pool_disk_name)" mklabel gpt &&
    exec_on_virt_node parted -a optimal "/dev/$(vm_storage_pool_disk_name)" mkpart primary ext4 0% 100% &&
    exec_on_virt_node mkfs.ext4 "/dev/$(vm_storage_pool_disk_name)"
}

mount_vm_storage_pool_disk() {
  local want got
  want="/dev/$(vm_storage_pool_disk_name)"
  got=$(exec_on_virt_node_directly systemctl status "/var/$VM_STORAGE_POOL_PATH" 2>/dev/null |
    grep 'What:' |
    awk '{print $NF}')
  test "$want" == "$got" && return 0

  info "Mounting VM storage pool disk '$(vm_storage_pool_disk_name)' to dir $VM_STORAGE_POOL_PATH"
  { exec_on_virt_node "test -d $VM_STORAGE_POOL_PATH" && exec_on_virt_node_directly "rm -rf $VM_STORAGE_POOL_PATH"; } || true
    exec_on_virt_node_directly systemd-mount "/dev/$(vm_storage_pool_disk_name)" "$VM_STORAGE_POOL_PATH"
}

set -e
add_vm_network_nic
add_vm_storage_pool_disk
format_vm_storage_pool_disk
mount_vm_storage_pool_disk

# shellcheck shell=bash

# exec_on_virt_node: Executes a command on the SNO node running Virt.
exec_on_virt_node() {
  node_name="$(exec_oc get nodes -o jsonpath='node/{.items[0].metadata.name}')"
  if test -z "$node_name"
  then
    error "Couldn't resolve SNO node name"
    return 1
  fi
  exec_oc debug -q "$node_name" -- "$@"
}

# exec_on_virt_node_directly: exec_on_virt_node, but in the host context.
exec_on_virt_node_directly() {
  args+=('chroot' '/host')
  args+=("$@")
  exec_on_virt_node "${args[@]}"
}

# vm_storage_pool_disk_name: The device ID for the VM storage pool disk (i.e. 'dnvme1n1')
vm_storage_pool_disk_name() {
  disk_names=$(exec_on_virt_node lsblk -d -o NAME | grep -E '^nvme' | grep -Ev '^nvme0')
  if test -z "$disk_names"
  then
    error "Unable to get disk names from node '$node_name'"
    return 1
  fi
  if test "$(wc -l <<< "$disk_names")" -gt 1
  then
    error "More than one disk found; there should only be one: $disk_names"
    return 1
  fi
  head -1 <<< "$disk_names"
}


#!/usr/bin/env bash
# Performs postinstall steps.
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/gitops.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"
patch_nncp_for_vm_network() {
  _find_physical_iface_members_in_brex_bridge() {
    pod=$(exec_oc get pod -n openshift-ovn-kubernetes \
      --field-selector=spec.nodeName="$1" \
      -l app=ovnkube-node \
      -o name)
    if test -z "$pod"
    then
      error "ovn pod not found on worker node '$1'"
      return 1
    fi
    exec_oc exec -q -n openshift-ovn-kubernetes "$pod" -- ovs-vsctl list-ports br-ex |
      grep -Ev '^patch-' |
      sort
  }

  _find_physical_ifaces_on_node() {
    exec_oc debug -q "node/$1" -- ip -br a | grep -E '^(en|eth)' | awk '{print $1}' | sort
  }

  _find_unclaimed_ifaces() {
    local all claimed
    all="$1"
    claimed="$2"
    comm -23 <(echo "$all") <(echo "$claimed") | sort -u
  }

  _nad_config() {
    local br_name vlan_id
    br_name="$1"
    vlan_id="${2:-100}"
    cat <<-EOF | jq tostring | sed 's/^"// ; s/"$//'
{
  "cniVersion": "0.3.1",
  "name": "bridge-network",
  "type": "bridge",
  "bridge": "$br_name",
  "macspoofchk": false,
  "vlan": $vlan_id,
  "disableContainerInterface": true,
  "preserveDefaultVlan": false
}
EOF
  }

  _patch_nncp_kustomization() {
    modifications="$(cat <<-EOF
- file: bootstrap/resources/networking/kustomization.yaml
  target:
    name: example-bridge-policy
  variables:
    "metadata/name": "br1-${1}-policy"
    "desiredState.*bridge/port.*": "$1"
- file: bootstrap/resources/networking/kustomization.yaml
  target:
    name: nad
  variables:
    'metadata/name': vm-bridge-network
    "resourceName": "bridge.network.kubevirt.io/br1"
    "config": "$(_nad_config br1)"
EOF
)"
    render_kustomization_patches "$modifications"
  }

  all_available_ifaces=""
  for node in $(exec_oc get nodes -o name | sed 's;^node/;;')
  do
    all_ifaces=$(_find_physical_ifaces_on_node "$node")
    claimed_ifaces=$(_find_physical_iface_members_in_brex_bridge "$node")
    available_ifaces=$(_find_unclaimed_ifaces "$all_ifaces" "$claimed_ifaces")
    all_available_ifaces="$all_available_ifaces $available_ifaces"
  done
  all_available_ifaces=$(tr ' ' '\n' <<< "$all_available_ifaces" | tr -d ' ' | grep -Ev '^$' | sort -u)
  if test -z "$all_available_ifaces"
  then
    error "No available interfaces found (found: [$(tr '\n' ',' <<< "$all_ifaces" | sed 's/.$//')], claimed: [$claimed_ifaces])"
    return 1
  fi
  num_unique_available_ifaces=$(wc -l <<< "$all_available_ifaces")
  if test "$num_unique_available_ifaces" -gt 1
  then
    error "One or more nodes have mismatched network interface device identifiers; interfaces: $all_available_ifaces"
    return 1
  fi
  patches=$(_patch_nncp_kustomization "$(head -1 <<< "$all_available_ifaces")") || return 1
  test "$patches" -eq 0 && return 0

  info "NodeNetworkConfigurationPolicy kustomization updated. Commit and push your changes to apply."
  return 1
}

_exec_on_virt_node() {
  node_name="$(exec_oc get nodes -o jsonpath='node/{.items[0].metadata.name}')"
  if test -z "$node_name"
  then
    error "Couldn't resolve SNO node name"
    return 1
  fi
  exec_oc debug -q "$node_name" -- "$@"
}

_vm_storage_pool_disk_name() {
  disk_names=$(_exec_on_virt_node lsblk -o NAME -J |
    jq_strip_null -r '[.blockdevices[] | select(.name | test("^nvme[?!0]"))] | flatten | .[].name')
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

patch_storage_machineconfig() {
  disk_name=$(_vm_storage_pool_disk_name)
  modifications="$(cat <<-EOF
- file: bootstrap/resources/storage/kustomization.yaml
  options:
    replace_all_match: true
  variables:
    device: "$disk_name"
    path: "$VM_STORAGE_POOL_PATH"
EOF
)"
  if ! patches="$(render_kustomization_patches "$modifications")"
  then
    error "Something went wrong while rendering kustomzations; see errors above."
    return 1
  fi
  test "$patches" -eq 0 && return 0

  info "Base resources kustomization updated. Commit and push your changes to apply."
  return 1
}

wait_for_vm_storage_pool_disk_to_mount() {
  disk_name=$(_vm_storage_pool_disk_name) || return 1
  local attempts=1
  while test "$attempts" -lt 60
  do
    info "[${attempts}/60] Waiting for VM storage pool disk '$disk_name' to mount onto '$VM_STORAGE_POOL_PATH'"
    mounts_found=$(_exec_on_virt_node mount | grep "$disk_name")
    test -n "$mounts_found" && return 0
    attempts=$((attempts+1))
    sleep 1
  done
  error "Timed out while waiting for disk to mount"
  return 1
}

patch_nncp_for_vm_network || exit 1
patch_storage_machineconfig || exit 1
setup_gitops ocp-on-ocp-aws bootstrap/operators operators
setup_gitops ocp-on-ocp-aws bootstrap/resources/base resources
setup_gitops ocp-on-ocp-aws bootstrap/resources/networking networking
setup_gitops ocp-on-ocp-aws bootstrap/resources/storage storage
wait_for_vm_storage_pool_disk_to_mount
info "WIP."
exit 0

wait_for_osv_to_become_ready
if ! nested_ocp_cluster_created
then
  render_install_config
  create_ocp_install_iso
  upload_ocp_install_iso_into_cluster
fi
setup_gitops ocp-on-ocp-aws bootstrap/resources/machines virtual-machines

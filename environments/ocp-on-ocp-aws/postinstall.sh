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

  _patch_nncp_kustomization() {
    modifications="$(cat <<-EOF
- file: bootstrap/resources/networking/kustomization.yaml
  variables:
    name: "br1-$1-policy"
    desiredState: "$1"
EOF
)"
    render_kustomization_patches "$modifications"
  }

  all_available_ifaces=""
  for node in $(_exec_oc get nodes -o name)
  do
    all_ifaces=$(_find_physical_ifaces_on_node "$node")
    claimed_ifaces=$(_find_physical_iface_members_in_brex_bridge "$node")
    available_ifaces=$(_find_unclaimed_ifaces "$all_ifaces" "$claimed_ifaces")
    all_available_ifaces="$all_available_ifaces $available_ifaces"
  done
  all_available_ifaces=$(tr ' ' '\n' <<< "$all_available_ifaces" | sort -u)
  num_unique_available_ifaces=$(wc -l <<< "$all_available_ifaces")
  if test "$num_unique_available_ifaces" -gt 1
  then
    error "One or more nodes have mismatched network interface device identifiers; interfaces: $all_available_ifaces"
    return 1
  fi
  patches=$(_patch_nncp_kustomization "$all_available_ifaces")
  test "$patches" -eq 0 && return 0

  info "NodeNetworkConfigurationPolicy kustomization updated. Commit and push your changes to apply."
  return 1
}

patch_nncp_for_vm_network || return 1
setup_gitops ocp-on-ocp-aws bootstrap/operators operators
setup_gitops ocp-on-ocp-aws bootstrap/resources/base resources
setup_gitops ocp-on-ocp-aws bootstrap/resources/networking networking
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

#!/usr/bin/env bash
# Destroys resources created within this environment.
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
source "$ENVIRONMENT_INCLUDE_DIR/rosa.sh"

# The 'delete' command doesn't have a 'network' subcommand, so we
# have to destroy the network "manually."
destroy_network() {
}

destroy_account_roles() {
  roles=$(aws iam list-roles | grep "$(_rosa_cluster_name)" | cat)
  test "$(wc -l <<< "$roles")" -le 1 && return 0

  info "Deleting ROSA account roles"
  rosa delete account-roles \
    --classic \
    --hosted-cp \
    --prefix "$(_rosa_cluster_name)" \
    --mode auto \
    --yes
}

destroy_oidc_configuration() {
  _oidc_config_created || return 0

  info "Deleting AWS OIDC config for ROSA"
  rosa delete oidc-config \
    --mode auto \
    --yes
}

destroy_operator_roles_classic() {
  _operator_roles_created classic || return 0

  info "Destroying ROSA HCP operator roles"
  _exec_rosa delete operator-roles \
    --mode=auto \
    --prefix="$(_rosa_cluster_name)-classic" \
    --yes
}

destroy_operator_roles_hcp() {
  _operator_roles_created hcp || return 0

  info "Destroying ROSA HCP operator roles"
  _exec_rosa delete operator-roles \
    --mode=auto \
    --prefix="$(_rosa_cluster_name)-hcp" \
    --yes
}


destroy_cluster_classic() {
  _all_clusters classic >/dev/null || return 0

  _cluster_uninstalling classic || rosa delete cluster \
    --cluster "$(_rosa_cluster_name)-classic" \
    --yes

  _wait_for_cluster_deleted classic
}

destroy_cluster_hcp() {
  _all_clusters hcp >/dev/null || return 0

  _cluster_uninstalling hcp || rosa delete cluster \
    --cluster "$(_rosa_cluster_name)-hcp" \
    --yes

  _wait_for_cluster_deleted hcp
}

set -e
destroy_cluster_hcp
destroy_cluster_classic
destroy_operator_roles_hcp
destroy_operator_roles_classic
destroy_oidc_configuration
destroy_account_roles
destroy_network

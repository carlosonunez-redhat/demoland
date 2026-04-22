#!/usr/bin/env bash
# Exposes data and secrets between environments during a deployment run.
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
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"
source "$ENVIRONMENT_INCLUDE_DIR/rosa.sh"
generate_kubeconfig() {
  cluster_name="$(_rosa_cluster_name)-$1"
  temp_password="Temp$(date +%s)$(tr -dc '[:alnum:]' < /dev/urandom | head -c 16)"

  _delete_temp_admin_user() {
      info "Deleting previous cluster admin in cluster '$cluster_name'"
    _exec_rosa delete admin -c "$cluster_name" --yes
  }

  _create_temp_admin_user() {
    _exec_rosa list idp -c "$cluster_name" | grep -q cluster-admin && _delete_temp_admin_user
    while test "$attempts" -ne "$max_attempts"
    do
      _exec_rosa create admin -c "$cluster_name" -p "$temp_password" && return 0
      info "Waiting for cluster-admin to be deleted in cluster '$cluster_name' (attempt $attempts of $max_attempts)"
      sleep 1
    done
  }

  _login() {
    attempts=0
    max_attempts=120
    while test "$attempts" -ne "$max_attempts"
    do
      oc login "$(_rosa_cluster_api_url "$1")" \
        --username cluster-admin \
        --password "$temp_password" && return 0
      info "Waiting for cluster-admin to become available on cluster '$cluster_name' (attempt $attempts of $max_attempts)"
      sleep 1
      attempts=$((attempts+1))
    done
    return 1
  }

  _save_kubeconfig() {
    cat $HOME/.kube/config > "$(_get_file_from_shared_secret_dir "kubeconfigs/$(_rosa_cluster_name "$1").kubeconfig")"
  }
  _create_temp_admin_user "$1" &&
    _login "$1" &&
    _save_kubeconfig "$1" &&
    _delete_temp_admin_user "$1"
}

yay_success() {
  info "Your ROSA clusters are ready.

Kubeconfigs:

$(find "$(_get_file_from_shared_secret_dir "kubeconfigs")" -type f -name '*kubeconfig*' |
  grep "$(_rosa_cluster_name)" |
  sed -E 's/^/- /')

Console URLs (log in with Google):

- Classic (if enabled): $(_rosa_cluster_console_url classic)
- HCP (if enabled): $(_rosa_cluster_console_url hcp)"
}

generate_kubeconfig classic
generate_kubeconfig hcp
yay_success

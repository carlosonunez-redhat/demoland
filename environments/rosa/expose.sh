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

  _login() {
    user=$(_get_from_config '.deploy.cluster_config.cluster_auth.basic.auths[] | select(.role == "cluster-admin") | .users[0].name')
    password=$(_get_from_config '.deploy.cluster_config.cluster_auth.basic.auths[] | select(.role == "cluster-admin") | .users[0].password')
    oc login "$(_rosa_cluster_api_url "$1")" \
      --username "$user" \
      --password "$password" && return 0
  }

  _save_kubeconfig() {
    fp="$(_get_file_from_shared_secret_dir "kubeconfigs/$(_rosa_cluster_name "$1").kubeconfig")"
    cat "$HOME/.kube/config" > "$fp"
    echo "$fp" > /environment_info/kubeconfig_path
  }
  _rosa_cluster_type_disabled "$1" && return 0

    _login "$1" &&
    _save_kubeconfig "$1"
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

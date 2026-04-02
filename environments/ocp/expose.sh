#!/usr/bin/env bash
set -e

source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"

_kubeconfig_file() {
  _get_file_from_shared_secret_dir "kubeconfigs/$(_cluster_name).kubeconfig"
}

expose_cluster_kubeconfig() {
  f=$(_kubeconfig_file)
  d="$(dirname "$(_kubeconfig_file)")"
  test -e "$f" && return 0
  info "Saving cluster kubeconfig to '$f'"
  test -d "$d" || mkdir -p "$d"
  cp "$(_get_file_from_data_dir "openshift-install/auth/kubeconfig")" "$f"
}

yay_success() {
  local console_url
  console_url="$(exec_oc get console cluster -o jsonpath='{.status.consoleURL}')"
  if test -z "$console_url"
  then
    warning "Couldn't find console URL for cluster $(_cluster_name); check manually: \
$(print_oc_command get console cluster -o jsonpath='{.status.consoleURL}')"
    return 0
  fi
  kubeadmin_password=$(cat "$(_get_file_from_data_dir 'openshift-install/auth/kubeadmin-password')")
  info "Your OpenShift cluster is ready! Here are your login details:

URL: $console_url
Username: kubeadmin
Password: $kubeadmin_password"
}

expose_cluster_kubeconfig || exit 1
yay_success

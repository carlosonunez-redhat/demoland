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

login_details() {
  users_from_config=$(_get_from_config '.deploy.cluster_config.cluster_auth.basic.auths[] | select(.role == "cluster-admin") | .users[].name')
  if test -z "$users_from_config"
  then
    kubeadmin_password=$(cat "$(_get_file_from_openshift_install_dir 'auth/kubeadmin-password')")
    printf "Username: %s\nPassword: %s\n" kubeadmin "$kubeadmin_password"
    return 0
  fi
  echo "Usernames:"
  echo "$users_from_config" | sed -E 's/^(.*)/- \1/'
  echo "(Decrypt the config file to see their passwords.)"
}

expose_cluster_kubeconfig() {
  expose_kubeconfig "$(cat "$(_get_file_from_openshift_install_dir 'auth/kubeconfig')")"
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
  kubeadmin_password=$(cat "$(_get_file_from_openshift_install_dir 'auth/kubeadmin-password')")
  info "Your OpenShift cluster is ready! Here are your login details:

URL: $console_url
$(login_details)"
}

expose_cluster_kubeconfig || exit 1
yay_success

#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/gcp.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
source "$ENVIRONMENT_INCLUDE_DIR/ocp.sh"

bootstrap_with_gitops() {
  set -e
  values=(
    repo_url "$(_get_secret 'gitops/repo')"
    repo_branch "$(_get_secret 'gitops/branch')"
    ssh_private_key_enc "$(_get_secret 'gitops/key' | base64 -w 0)"
  )
  secrets_f="/tmp/gitops_secret_$(_cluster_name)"
  app_f="/tmp/gitops_app_$(_cluster_name)"
  info "Setting up 'bootstrap' GitOps application"
  render_yaml_template repo_credentials_secret "${values[@]}"  > "$secrets_f" &&
    render_yaml_template gitops_application "${values[@]}" > "$app_f" &&
    exec_oc_postinstall apply -f "$secrets_f" &&
    exec_oc_postinstall apply -f "$app_f"
}

configure_gitops_admins() {
  admins=$(_get_from_config '.deploy.cluster_config.cluster_auth |
    to_entries |
    .[].value.auths[] |
    select(.role == "cluster-admin") |
    .users[].name' | grep -Ev '^null$' | cat)
  test -z "$admins" && return 0

  if ! { exec_oc_postinstall get groups -o name | grep -Eq '.*/cluster-admins$'; }
  then
    info "Creating ArgoCD 'cluster-admins' group"
    exec_oc_postinstall adm groups new cluster-admins
  fi
  for user in $admins
  do
    info "Adding '$user' to 'cluster-admins'"
    exec_oc_postinstall adm groups add-users cluster-admins "$user"
  done
}

configure_gitops_admins
bootstrap_with_gitops

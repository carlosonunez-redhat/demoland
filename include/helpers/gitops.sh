# shellcheck shell=bash

# setup_gitops @ENVIRONMENT_NAME @GITOPS_FOLDER @APP_NAME:
#
# Creates an ArgoCD Application for an environment assuming
# that the following secrets exist for an environment (or its dependent environments)
# in `config.yaml` AND that the environment has a folder called `gitops` (or @GITOPS_FOLDER) in its
# toplevel directory:
#
# - gitops/repo: The demoland repository to connect this App to.
# - gitops/branch: The branch in `gitops/repo` to sync with.
# - gitops/key: The SSH private key to use when cloning `gitops/repo` (enables
#   cloning private Demoland repos)
setup_gitops() {
  local environment_name gitops_dir app_name
  environment_name="$1"
  if test -z "$environment_name"
  then
    error "GitOps environment name missing."
    return 1
  fi
  gitops_dir="${2:-gitops}"
  app_name="${3:-$environment_name}"
  set -e
  values=(
    repo_url "$(_get_secret 'gitops/repo')"
    repo_branch "$(_get_secret 'gitops/branch')"
    ssh_private_key_enc "$(_get_secret 'gitops/key' | base64 -w 0)"
    environment_name "$environment_name"
    gitops_dir "$gitops_dir"
    app_name "$app_name"
  )
  secrets_f="/tmp/gitops_secret_$(_cluster_name)"
  app_f="/tmp/gitops_app_$(_cluster_name)"
  info "Setting up '$app_name' GitOps application"
  render_include_yaml_template repo_credentials_secret "${values[@]}"  > "$secrets_f" &&
    render_include_yaml_template gitops_application "${values[@]}" > "$app_f" &&
    exec_oc_postinstall apply -f "$secrets_f" &&
    exec_oc_postinstall apply -f "$app_f"
}

# configure_gitops_admins: Makes every user with a 'cluster-admin' cluster role mapping
# an admin in ArgoCD/OpenShift GitOps.
#
# See also: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/html-single/managing_cluster_configuration/index#configuring-rbac_managing-openshift-cluster-configuration
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

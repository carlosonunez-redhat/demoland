# shellcheck shell=bash
source "$(dirname "$0")/../include/helpers/ocp.sh"

_wait_for_gitops_ready() {
  _namespace_available() {
    "$exec_oc_fn" get ns | grep -q 'openshift-gitops' && return 0
    warning "[gitops] readiness: namespace available"
    return 1
  }

  _application_crd_installed() {
    "$exec_oc_fn" api-resources -o name | grep -q 'applications.argoproj.io' && return 0
    warning "[gitops] readiness: Application CRD unavailable"
    return 1
  }
  attempts=0
  max_attempts=180
  exec_oc_fn="$1"
  while test "$attempts" -lt "$max_attempts"
  do
    _namespace_available && _application_crd_installed && return 0
    info "[gitops] Waiting for prerequisites [attempt $attempts of $max_attempts]"
    attempts=$((attempts+1))
    sleep 1
  done
}

_setup_gitops() {
  local environment_name gitops_dir app_name exec_oc_fn
  environment_name="$1"
  if test -z "$environment_name"
  then
    error "GitOps environment name missing."
    return 1
  fi
  gitops_dir="${2:-gitops}"
  app_name="${3:-$environment_name}"
  exec_oc_fn="$4"
  set -e
  if ! _wait_for_gitops_ready "$exec_oc_fn"
  then
    error "[gitops] Failed to become ready"
    return 1
  fi
  values=(
    repo_url "$(_get_secret 'gitops/repo')"
    repo_branch "$(_get_secret 'gitops/branch')"
    ssh_private_key_enc "$(_get_secret 'gitops/key' | base64 -w 0)"
    environment_name "$environment_name"
    gitops_dir "$gitops_dir"
    app_name "$app_name"
  )
  secrets_f="/tmp/gitops_secret_$(date +%s)"
  app_f="/tmp/gitops_app_$(date +%s)"
  info "Setting up '$app_name' GitOps application (environment: $environment_name)"
  render_include_yaml_template repo_credentials_secret "${values[@]}"  > "$secrets_f" &&
    render_include_yaml_template gitops_application "${values[@]}" > "$app_f" &&
    "$exec_oc_fn" apply -f "$secrets_f" &&
    "$exec_oc_fn" apply -f "$app_f"
}

_configure_gitops_admins() {
  exec_oc_fn="$1"
  admins=$(_get_from_config '.deploy.cluster_config.cluster_auth |
    to_entries |
    .[].value.auths[] |
    select(.role == "cluster-admin") |
    .users[].name' | grep -Ev '^null$' | cat)
  test -z "$admins" && return 0

  if ! { "$exec_oc_fn" get groups -o name | grep -Eq '.*/cluster-admins$'; }
  then
    info "Creating ArgoCD 'cluster-admins' group"
    "$exec_oc_fn" adm groups new cluster-admins
  fi
  for user in $admins
  do
    info "Adding '$user' to 'cluster-admins'"
    "$exec_oc_fn" adm groups add-users cluster-admins "$user"
  done
}
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

# configure_gitops_admins: Makes every user with a 'cluster-admin' cluster role mapping
# an admin in ArgoCD/OpenShift GitOps.
#
# See also: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.20/html-single/managing_cluster_configuration/index#configuring-rbac_managing-openshift-cluster-configuration
setup_gitops() {
  _setup_gitops "$1" "$2" "$3" 'exec_oc'
}

# setup_gitops_postinstall @ENVIRNOMENT_NAME @GITOPS_FOLDER @APP_NAME:
#
# Same as 'setup_gitops', but uses the cluster kubeconfig in the 'openshift-install'
# directory instead of the kubeconfig in the environment's toplevel directory.
setup_gitops_postinstall() {
  _setup_gitops "$1" "$2" "$3" 'exec_oc_postinstall'
}

# configure_gitops_admins: Maps users with the `cluster-admin` role to ArgoCD's list of admins.
configure_gitops_admins() {
  _configure_gitops_admins 'exec_oc'
}

# configure_gitops_admins_postinstall: `configure_gitops_admins`, but after an OpenShift
# cluster bring-up.
configure_gitops_admins_postinstall() {
  _configure_gitops_admins 'exec_oc_postinstall'
}

# render_kustomization_patches @YAML
# Renders a Kustomization in an environment based on the YAML provided
# by `@YAML`. Schema is below:
#
# ```yaml
# ---
# - file: string # path to kustomization file
#   variables:
#     key: string # `key` is a part of a path in a patch to modify.
#                 # `value` is the desired value for that patch.
modify_kustomizations() {
  local replacements_made mod_yaml want got curr_mods patch_json
  replacements_made=0
  mod_yaml="$(yq -r '.' <<< "$1")"
  if test -z "$mod_yaml"
  then
    error "Kustomization modifications YAML empty or malformed: $1"
    return 1
  fi
  while read -r fname
  do
    file="$(_get_environment_dir)/$fname"
    curr_mods=$(yq -r '.[] | select(.file | contains("'"$fname"'"))' <<< "$mod_yaml")
    while read -r patch_json
    do
      while read -r var
      do
        got_json=$(jq -r '.[] | select(.path | test(".*/'"$var"'$")) | .' <<< "$patch_json" | grep -Ev '^null$' | cat)
        test -z "$got_json" && continue
        got=$(jq -r '.value' <<< "$got_json")
        want=$(yq -r '.variables | to_entries[] | select(.key == "'"$var"'") | .value' <<< "$curr_mods")
        test "$want" == "$got" && continue
        replacements_made=$((replacements_made+1))
        info "===> Modifying kustomization '$file' (key: '$var', want: '$want', got: '$got')"
        sed -i "s;$got;$want;g" "$file"
      done < <(yq -r '.variables | to_entries[] | .key' <<< "$curr_mods")
    done < <(yq -o=j -I=0 -r '.patches[].patch | fromyaml' "$file")
  done < <(yq -r '.[].file' <<< "$mod_yaml")
  echo "$replacements_made"
}


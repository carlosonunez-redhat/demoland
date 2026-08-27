# shellcheck shell=bash
source "$(dirname "$0")/../include/helpers/ocp.sh"
source "$(dirname "$0")/../include/helpers/yaml.sh"

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
# # file: path to a Kustomization file to manipulate
# - file: string
#   target:
#     # target.name: The name of the resource in the Kustomization whose patch is being altered
#     name: ""
#     # target.kind: The Kind of the resource in the Kustomization whose patch is being altered
#     kind: ""
#   variables:
#     # variables.[path]: A mapping of a regexp for a resource path in the patch JSON to alter to its value.
#     #                   The value can be any JSON-acceptable object.
#     key: $value
# ```
#
render_kustomization_patches() {
  _path_values_are_equal() {
    test "$(base64 -w 0 <<< "$1")" == "$(base64 -w 0 <<< "$2")"
  }

  local modifications_made modifications_yaml
  modifications_made=0
  modifications_yaml="$1"
  if test -z "$modifications_yaml"
  then
    error "Modifications YAML is empty"
    return 1
  fi
  if ! &>/dev/null yq . <<< "$modifications_yaml"
  then
    error "Modifications YAML is malformed"
    return 1
  fi
  while read -r modification_data
  do
    kustomization_file_str=$(jq_strip_null -r '.file' <<< "$modification_data")
    if test -z "$kustomization_file_str"
    then
      error "File is missing in modification block '$modification_data'"
      return 1
    fi
    kustomization_file_str="$(_get_environment_dir)/$kustomization_file_str"
    if ! test -f "$kustomization_file_str"
    then
      error "Kustomization file not found: $kustomization_file_str"
      return 1
    fi
    modifications=$(jq_strip_null -r '.variables' <<< "$modification_data")
    if test -z "$modifications"
    then
      error "Modification block is missing modifications: $modification_data"
      return 1
    fi
    kustomization=$(yq -r '.' "$kustomization_file_str")
    this_target_name=$(jq_strip_null -r '.target.name' <<< "$modification_data")
    this_target_kind=$(jq_strip_null -r '.target.kind' <<< "$modification_data")
    for patch_idx in $(seq 0 "$(yq -r '(.patches | length) - 1' <<< "$kustomization")")
    do
      patch_statement=$(yq -r ".patches[$patch_idx]" <<< "$kustomization")
      patch_target_name=$(yq_strip_null -r '.target.name' <<< "$patch_statement")
      patch_target_kind=$(yq_strip_null -r '.target.kind' <<< "$patch_statement")
      { test -n "$this_target_name" && { test "$this_target_name" != "$patch_target_name"; } ; } && continue
      { test -n "$this_target_kind" && { test "$this_target_kind" != "$patch_target_kind"; } ; } && continue
      patch_statement_json=$(yq -o=j -I=0 -r ".patch | from_yaml" <<< "$patch_statement")
      while read -r modification
      do
        mod_path_regexp=$(jq -r '.key' <<< "$modification")
        paths_found=$(jq --arg re "$mod_path_regexp" -r '[.[] | select(.path | test($re)) | .path] | flatten' <<< "$patch_statement_json")
        paths_found_length=$(jq -r 'length' <<< "$paths_found")
        if test "$paths_found_length" -gt 1
        then
          error "Multiple paths found that match '$mod_path_regexp'; only one is allowed: $paths_found"
          return 1
        fi
        path_found=$(jq -r '.[0]' <<< "$paths_found")
        current_path_value="$(jq -cr --arg path "$path_found" '.[] | select(.path == $path) | .value' <<< "$patch_statement_json")"
        new_path_value=$(jq -cr '.value' <<< "$modification")
        _path_values_are_equal "$current_path_value" "$new_path_value" && continue
        info "Modifying path '$path_found' in kustomization '$kustomization_file_str'; current: '$current_path_value', new: '$new_path_value'"
        new_patch_statement_json=$(jq --arg path "$path_found" \
          --arg val "$new_path_value" \
          -r \
          '(.[] | select(.path == $path) | .value) = ($val | tostring)' <<< "$patch_statement_json")
        yq -i "(.patches[$patch_idx].patch) = ($new_patch_statement_json | to_yaml)" "$kustomization_file_str" ||
          return 1
        modifications_made=$((modifications_made+1))
      done < <(yq -o=j -I=0 -r '. | to_entries[]' <<< "$modifications")
    done
  done < <(yq -o=j -I=0 -r '.[]' <<< "$modifications_yaml")
  echo "$modifications_made"
}

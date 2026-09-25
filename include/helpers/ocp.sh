# shellcheck shell=bash
_cluster_name() {
    _get_top_level_environment_name |
      tr -dc '[:alnum:]' |
      head -c 18
}

_ocp_cluster_name() {
  printf "%s-%s"  \
    "$(_cluster_name)" \
    "$(_get_this_environment_id)" |
    head -c 20
}

_cluster_infra_name() {
  printf "demoland-%s-%s" \
    "$(_get_top_level_environment_id | tr '[:upper:]' '[:lower:]' | head -c 8)" \
    "$(_get_this_environment_id)" | head -c 20
}

_cluster_ignition_files_bucket() {
  local from_secret
  from_secret=$(_get_secret_quiet ocp/ignition_files_bucket)
  if test -n "$from_secret"
  then
    echo "$from_secret"
    return 0
  fi
  printf "%s-%s-ocp-ignition-files" "$(_cluster_name)" "$(_get_top_level_environment_name)" |
    tr '[:upper:]' '[:lower:]'
}

_oc_cmd() {
  local oc_bin
  oc_bin="${OC_BIN:-/usr/local/bin/oc}"
  cmd=("$oc_bin" --kubeconfig "$1" "${@:2}")
  echo "${cmd[@]}"
}

_helm_cmd() {
  local helm_bin
  helm_bin="${HELM_BIN:-/usr/sbin/helm}"
  cmd=("$helm_bin" --kubeconfig "$1" "${@:2}")
  echo "${cmd[@]}"
}

_exec_oc() {
  command -- $(_oc_cmd "$1" "${@:2}")
}

_exec_helm() {
  command -- $(_helm_cmd "$1" "${@:2}")
}

_retrieve_env_kubeconfig() {
  if test "${2,,}" == external
  then
    if test -z "$3"
    then
      error "API endpoint required for external env '$2'"
      return 1
    fi
    kubeconfigs=$(list_external_kubeconfigs "$3")
  else
    kubeconfigs=$(list_env_kubeconfigs)
    test -n "$1" && kubeconfigs=$(echo "$kubeconfigs" | grep -E "/${1}\$")
  fi
  num_kubeconfigs=$(wc -l <<< "$kubeconfigs")
  if test "$num_kubeconfigs" -eq 0
  then
    errmsg="No kubeconfigs found for environment '$(_get_top_level_environment_name)'"
    test -n "$1" && errmsg="$errmsg (base env requested: $1)"
    test "${2,,}" == external && errmsg="$errmsg (external demo env: $2)"
    error "$errmsg"
    return 1
  fi
  chosen_kubeconfig=$(head -1 <<< "$kubeconfigs")
  if test "$num_kubeconfigs" -gt 1
  then
    if test "${2,,}" == external
    then warnmsg="Multiple kubeconfigs match external demo environment '$1'; \
choosing '$(basename "$chosen_kubeconfig")'"
    else warnmsg="Multiple kubeconfigs written for environment $(_get_top_level_environment_name); \
choosing '$(basename "$chosen_kubeconfig")' (use 'exec_oc_by_environment_name' to select \
an environment)"
    fi
    warn "$warnmsg"
  fi
  if test "$2" == external
  then echo "$chosen_kubeconfig"
  else cat "$chosen_kubeconfig"
  fi
}

_retrieve_external_env_kubeconfig() {
  _retrieve_env_kubeconfig "$1" external "$2"
}

list_env_kubeconfigs() {
  find "/environment_info/kubeconfigs/$(_get_top_level_environment_name)" -mindepth 1 -type f | sort -u
}

list_external_kubeconfigs() {
  grep -Elr "server: https://$1" /shared/secrets/kubeconfigs | sort -u
}

exec_oc() {
  _exec_oc "$(_retrieve_env_kubeconfig)" "$@"
}

exec_oc_by_environment_name() {
  _exec_oc "$(_retrieve_env_kubeconfig "$1")" "${@:2}"
}

exec_oc_external_demo_environment() {
  _exec_oc "$(_retrieve_external_env_kubeconfig "$1" "$2")" "${@:3}"
}

exec_helm() {
  _exec_helm "$(_retrieve_env_kubeconfig)" "$@"
}

exec_helm_by_environment_name() {
  _exec_helm "$(_retrieve_env_kubeconfig "$1")" "${@:2}"
}

exec_helm_external_demo_environment() {
  _exec_helm "$(_retrieve_external_env_kubeconfig "$1" "$2")" "${@:3}"
}

exec_oc_postinstall() {
  config=$(_get_file_from_openshift_install_dir 'auth/kubeconfig')
  ctx=$(_exec_oc "$config" config get-contexts -o name | grep -E '^(system:admin|admin|kube:admin)$')
  if test -z "$ctx"
  then
    error "Couldn't find 'kube:admin' context from openshift-install generated Kubeconfig"
    return 1
  fi
  _exec_oc "$(_get_file_from_openshift_install_dir 'auth/kubeconfig')" --context "$ctx" "$@"
}

print_oc_command() {
  _oc_cmd "$(_retrieve_env_kubeconfig)" "$@"
}

# saves a kubeconfig into the secret dir while also writing a reference to
# it in the toplevel environment volume.
expose_kubeconfig() {
  local kubeconfig_ref kubeconfig_path
  kubeconfig_ref_name="$(_get_this_environment_name)"
  test "$(_get_top_level_environment_name)" == "$(_get_this_environment_name)" && kubeconfig_ref_name=self
  kubeconfig_ref="/environment_info/kubeconfigs/$(_get_top_level_environment_name)/$kubeconfig_ref_name"
  test -d "$(dirname "$kubeconfig_ref")" || mkdir -p "$(dirname "$kubeconfig_ref")"
  if test -f "$kubeconfig_ref"
  then kubeconfig_path=$(cat "$kubeconfig_ref")
  else kubeconfig_path=$(mktemp -u "$(_get_file_from_shared_secret_dir "kubeconfigs")/XXXXXXXXXXXXXXXX.kubeconfig")
  fi
  info "Saving cluster kubeconfig to '$kubeconfig_path'"
  echo "$1" > "$kubeconfig_path" && echo "$kubeconfig_path" > "$kubeconfig_ref"
}

# cluster_fqdn: Gets the default FQDN of the cluster for use with other Routes.
cluster_fqdn() {
  exec_oc get route console -n openshift-console -o jsonpath='{.status.ingress[0].host}' |
    sed -E 's/^console-openshift-console.//'
}

# cluster_fqdn_base_environment: cluster_fqdn, but with a base environment
cluster_fqdn_base_environment() {
  exec_oc_by_environment_name "$1" get route console -n openshift-console -o jsonpath='{.status.ingress[0].host}' |
    sed -E 's/^console-openshift-console.//'
}

# print_env_kubeconfig: Retrieves and prints a kubeconfig for a base or demo environment.
print_env_kubeconfig() {
  kp=$(_retrieve_env_kubeconfig "$1") || return 1
  cat "$kp"
}

# print_external_demo_env_kubeconfig: Like `print_env_kubeconfig`, but for external demo denvs.
print_external_demo_env_kubeconfig() {
  kp=$(_retrieve_external_env_kubeconfig "$1" "$2") || return 1
  cat "$kp"
}

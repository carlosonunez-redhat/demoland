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
  printf "%s-ocp-ignition-files" "$(_ocp_cluster_name |
    base64 -w 0 |
    tr -d '=' |
    tr '[:upper:]' '[:lower:]' |
    head -c 12)"
}

_oc_cmd() {
  local oc_bin
  oc_bin="${OC_BIN:-/usr/local/bin/oc}"
  cmd=("$oc_bin" --kubeconfig "$1" "${@:2}")
  echo "${cmd[@]}"
}

_exec_oc() {
  command -- $(_oc_cmd "$1" "${@:2}")
}

_retrieve_env_kubeconfig() {
  kubeconfigs=$(find /environment_info/kubeconfigs -mindepth 1 -type f | sort -u)
  num_kubeconfigs=$(wc -l <<< "$kubeconfigs")
  chosen_kubeconfig=$(head -1 <<< "$kubeconfigs")
  if test "$num_kubeconfigs" -gt 1
  then
    warning "Multiple kubeconfigs written for environment $(_get_top_level_environment_name); \
choosing '$(basename "$chosen_kubeconfig")' (use 'exec_oc_by_environment_name' to select \
an environment)"
  fi
  cat "$chosen_kubeconfig"
}

exec_oc() {
  _exec_oc "$(_retrieve_env_kubeconfig)" "$@"
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
  kubeconfig_ref="/environment_info/kubeconfigs/$(_get_this_environment_name)"
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

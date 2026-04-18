# shellcheck shell=bash
_cluster_name() {
    _get_top_level_environment_name |
      tr -dc '[:alnum:]' |
      head -c 18
}

_cluster_infra_name() {
  printf "demoland-%s" "$(_get_top_level_environment_id | tr '[:upper:]' '[:lower:]' | head -c 8)"
}

_cluster_ignition_files_bucket() {
  printf "%s-ocp-ignition-files" "$(_cluster_name |
    base64 -w 0 |
    tr -d '=' |
    tr '[:upper:]' '[:lower:]' |
    head -c 12)"
}

_oc_cmd() {
  local oc_bin
  oc_bin="${OC_BIN:-/usr/bin/oc}"
  cmd=("$oc_bin" --kubeconfig "$1" "${@:2}")
  echo "${cmd[@]}"
}

_exec_oc() {
  command -- $(_oc_cmd "$1" "${@:2}")
}

exec_oc() {
  _exec_oc "$(cat /environment_info/kubeconfig_path)" "$@"
}

exec_oc_postinstall() {
  _exec_oc "$(_get_file_from_openshift_install_dir 'auth/kubeconfig')" "$@"
}

print_oc_command() {
  _oc_cmd "kubeconfigs/$(_cluster_name).kubeconfig" "$@"
}

# saves a kubeconfig into the secret dir while also writing a reference to
# it in the toplevel environment volume.
expose_kubeconfig() {
  local kubeconfig_ref kubeconfig_path
  kubeconfig_ref="/environment_info/kubeconfig_path"
  if test -f "$kubeconfig_ref"
  then kubeconfig_path=$(cat "$kubeconfig_ref")
  else kubeconfig_path=$(mktemp -u "$(_get_file_from_shared_secret_dir "kubeconfigs")/XXXXXXXXXXXXXXXX.kubeconfig")
  fi
  info "Saving cluster kubeconfig to '$kubeconfig_path'"
  test -d "$(dirname "$kubeconfig_path")" || mkdir -p "$(dirname "$kubeconfig_path")"
  echo "$1" > "$kubeconfig_path" && echo "$kubeconfig_path" > "$kubeconfig_ref"
}

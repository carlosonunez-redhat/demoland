# shellcheck shell=bash
_cluster_name() {
  printf "demoland-%s" "$(_get_top_level_environment_name | tr -dc '[:alnum:]')" |
    head -c 26
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
  _exec_oc "$(_get_file_from_shared_secret_dir "kubeconfigs/$(_cluster_name)").kubeconfig" "$@"
}

exec_oc_postinstall() {
  _exec_oc "$(_get_file_from_data_dir 'openshift-install/auth/kubeconfig')" "$@"
}

print_oc_command() {
  _oc_cmd "kubeconfigs/$(_cluster_name).kubeconfig" "$@"
}

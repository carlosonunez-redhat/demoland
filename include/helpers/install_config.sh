# shellcheck shell=bash
source "$(dirname "$0")/../include/helpers/errors.sh"
source "$(dirname "$0")/../include/helpers/yaml.sh"

_openshift_install_dir() {
  printf '%s/%s' \
    "$(_get_file_from_data_dir 'openshift-install')" \
    "$(_cluster_name)"
}

_get_file_from_openshift_install_dir() {
  printf '%s/%s' "$(_openshift_install_dir)" "$1"
}

_config_file_in_data_dir() {
  _get_file_from_openshift_install_dir 'install-config.yaml'
}

_config_file_dir() {
  dirname "$(_config_file_in_data_dir)"
}

_config_file_in_environment() {
  printf '%s/include/templates/install-config.yaml' "$(dirname "$0")"
}

_create_install_config_directory_if_not_exists() {
  test -d "$(_config_file_dir)" || mkdir -p "$(_config_file_dir)"
}

render_and_save_install_config() {
  _create_install_config_directory_if_not_exists
  info "Writing openshift-install file to $(_config_file_in_data_dir)"
  yaml=$(fail_if_nil \
    "$(render_yaml_template install-config "$@")" \
    "Couldn't generate AWS install config.") || return 1
  echo "$yaml" > "$(_config_file_in_data_dir)" || return 1
  test -f "$(_get_file_from_openshift_install_dir 'created_on')" && return 0

  date +%s > "$(_get_file_from_openshift_install_dir 'created_on')"
}

get_data_from_ignition_file() {
  local ign_type
  ign_type="$1"
  if test -z "$ign_type"
  then
    error "Need to provide ignition type"
    return 1
  fi
  ign_file=$(_get_file_from_openshift_install_dir "${ign_type}.ign")
  if ! test -f "$ign_file"
  then
    error "Couldn't find ignition file: $ign_file"
    return 1
  fi
  jq -r "$2" "$ign_file"
}

install_config_data_stale() {
  local twelve_hours_in_sec now install_config_creation_time delta secs_until_stale
  test -f "$(_get_file_from_openshift_install_dir 'created_on')" || return 1
  twelve_hours_in_sec=43200
  now=$(date +%s)
  install_config_creation_time=$(cat "$(_get_file_from_openshift_install_dir 'created_on')")
  delta=$((now-install_config_creation_time))
  secs_until_stale=$((twelve_hours_in_sec-delta))
  info "[openshift-install] $((secs_until_stale/60)) minutes until install-config metadata stale"
  test "$delta" -ge "$twelve_hours_in_sec"
}

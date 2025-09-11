# shellcheck shell=bash
source "$(dirname "$0")/../include/helpers/errors.sh"
source "$(dirname "$0")/../include/helpers/yaml.sh"

_config_file_in_data_dir() {
  printf '%s/openshift-install/install-config.yaml' "$(_get_file_from_data_dir)"
}

_config_file_dir() {
  dirname "$(_config_file_in_data_dir)"
}

_config_file_in_environment() {
  printf '%s/include/templates/install-config.yaml' "$(dirname "$0")"
}

_create_install_config_directory_if_not_exists() {
  test -d "$(_config_file_dir)" || mdkir -p "$(_config_file_dir)"
}

render_and_save_install_config() {
  _create_install_config_directory_if_not_exists
  info "Writing openshift-install file to $(_config_file_in_data_dir)"
  yaml=$(fail_if_nil \
    "$(render_yaml_template install-config "$@")" \
    "Couldn't generate AWS install config.") || return 1
  echo "$yaml" > "$(_config_file_in_data_dir)"
}

get_data_from_ignition_file() {
  local ign_type
  ign_type="$1"
  if test -z "$ign_type"
  then
    error "Need to provide ignition type"
    return 1
  fi
  ign_file="$(_get_file_from_data_dir "openshift-install/${ign_type}.ign")"
  if ! test -f "$ign_file"
  then
    error "Couldn't find ignition file: $ign_file"
    return 1
  fi
  jq -r "$2" "$ign_file"
}

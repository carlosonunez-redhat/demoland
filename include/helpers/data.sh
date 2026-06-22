_get_file_from_data_dir() {
  echo "/data/$1" | sed 's;//;/;g'
}

_get_files_from_data_dir() {
  find /data -type f -name "$1"
}

_get_file_from_secrets_dir() {
  echo "/secrets/${1}-$(_get_top_level_environment_id)"
}

_do_get_secret() {
  local f quiet
  f=$(_get_file_from_secrets_dir "$1")
  quiet="${2:-false}"
  test -n "$f" && 2>/dev/null cat "$f" && return 0

  test "${quiet,,}" == false &&
    error "Secret '$1' is not defined in '.deploy.secrets' section of this environment's config."
  return 1
}

_get_secret() {
  _do_get_secret "$1"
}

_get_secret_quiet() {
  _do_get_secret "$1" true
}

_get_file_from_shared_data_dir() {
  echo "/shared/data/$1" | sed 's;//;/;g'
}

_get_file_from_shared_secret_dir() {
  echo "/shared/secrets/$1" | sed 's;//;/;g'
}

_get_top_level_environment_name() {
  cat "/environment_info/root_environment_name"
}

_get_top_level_environment_id() {
  cat "/environment_info/root_environment_id"
}

_get_environment_dir() {
  echo '/app/environment'
}

_get_this_environment_name() {
  test -n "$ENVIRONMENT_NAME" && echo "$ENVIRONMENT_NAME"
  warning "Requested this environment name, but it's not set!"
}

_get_this_environment_id() {
  _get_this_environment_name | base64 -d | tr '[:upper:]' '[:lower:]' | head -c 8
}

_get_file_from_data_dir() {
  echo "/data/$1" | sed 's;//;/;g'
}

_get_files_from_data_dir() {
  find /data -type f -name "$1"
}

_get_file_from_secrets_dir() {
  echo "/secrets/${1}-$(_get_top_level_environment_id)"
}

_get_secret() {
  f=$(_get_file_from_secrets_dir "$1")
  test -n "$f" && cat "$f" && return 0

  error "Secret '$1' is not defined in '.deploy.secrets' section of this environment's config."
  return 1
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

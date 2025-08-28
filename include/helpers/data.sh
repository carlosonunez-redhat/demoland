_get_file_from_data_dir() {
  echo "/data/$1"
}

_get_files_from_data_dir() {
  find /data -type f -name "$1"
}

_get_file_from_secrets_dir() {
  echo "/secrets/$1"
}

_get_file_from_data_dir() {
  echo "/data/$1" | sed 's;//;/;g'
}

_get_files_from_data_dir() {
  find /data -type f -name "$1"
}

_get_file_from_secrets_dir() {
  echo "/secrets/$1"
}

_get_file_from_shared_data_dir() {
  echo "/shared/data/$1" | sed 's;//;/;g'
}

_get_file_from_shared_secret_dir() {
  echo "/shared/secrets/$1" | sed 's;//;/;g'
}

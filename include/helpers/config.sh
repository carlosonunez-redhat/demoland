_get_from_config() {
  q="$(sed -E 's;^\.;;' <<< "$1")"
  yq -r ".$q" "$(_get_file_from_secrets_dir 'config.yaml')" | grep -Ev '^null$'
}

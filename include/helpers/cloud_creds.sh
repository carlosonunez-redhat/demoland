_get_cloud_cred() {
  local provider cred_key q
  provider="$1"
  cred_key="$2"
  q=".$provider.$cred_key"
  result=$(yq -r "$(sed -E 's/\.{2,}/./g' <<< "$q")" "$(_get_file_from_secrets_dir 'cloud_creds.yaml')") || return 1
  grep -Ev '^null$' <<< "$result" | cat
}

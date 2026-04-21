source "$(dirname "$0")/../include/helpers/data.sh"
_get_from_config() {
  q="$(sed -E 's;^\.;;' <<< "$1")"
  yq -r ".$q" "$(_get_file_from_secrets_dir "config-$(_get_top_level_environment_id).yaml")" | grep -Ev '^null$' | cat
}

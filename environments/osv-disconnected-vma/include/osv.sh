# shellcheck shell=bash

_resolve_this_ip() {
  result=$(2>/dev/null curl -sS http://api.ipify.org)
  if test -n "$result" && grep -Eq '^([0-9]{1,3}.){3}[0-9]{1,3}$' <<< "$result"
  then
    echo "$result"
    return
  fi
  return 1
}
_bare_metal_instances_sentinel() {
  _get_file_from_data_dir 'aws_bill_go_brrrrrr_mode_on'
}

delete_bare_metal_instances_sentinel() {
  test -f "$(_bare_metal_instances_sentinel)" || return 0
    rm "$(_bare_metal_instances_sentinel)"
}

create_bare_metal_instances_sentinel() {
  touch "$(_bare_metal_instances_sentinel)"
}

exec_tofu() {
  if ! this_ip=$(_resolve_this_ip)
  then
    error "Failed to resolve this machine's IP; cannot continue"
    exit 1
  fi
  export TF_VAR_ssh_ip="$this_ip"
  export TF_VAR_bare_metal_creation_sentinel_file="$(_bare_metal_instances_sentinel)"
  tofu "$@"
}

# shellcheck shell=bash
_exec_tofu() {
  >/dev/null pushd /app/environment/infrastructure || return 1
  export TF_DATA_DIR="$(_get_file_from_data_dir 'tofu/data')"
  export TF_PLUGIN_DIR="$(_get_file_from_data_dir 'tofu/plugins')"
  export TF_CLI_ARGS_apply='-auto-approve'
  /usr/local/bin/tofu "$@" || return 1
  >/dev/null popd || return 1
}

_delete_tofu_state_s3() {
  # shellcheck disable=SC2016 # (not trying to run code here)
  info "Destroying Tofu state bucket post "'`tofu destroy`'
  aws s3 rb "s3://${TOFU_STATE_S3_BUCKET}"
}

_init_tofu() {
  test -n "$TOFU_REINIT" && rm -f "$(_get_file_from_data_dir tofu_initialized)"
  test -f "$(_get_file_from_data_dir tofu_initialized)" && return 0

  _exec_tofu init --reconfigure \
    --backend-config="bucket=${TOFU_STATE_S3_BUCKET}" \
    --backend-config="key=${TOFU_STATE_KEY}" \
    --backend-config="region=${AWS_DEFAULT_REGION}" || return 1

    touch "$(_get_file_from_data_dir tofu_initialized)"
}

tofu() {
  _init_tofu || return 1
  case "${1,,}" in
    preflight)
      return 0
      ;;
    apply)
      action=apply
      test -n "$DRY_RUN" && action=plan
      shift
      _exec_tofu "$action" "$@" || return 1
      ;;
    destroy)
      _exec_tofu "$@" || return 1
      _delete_tofu_state_s3
      ;;
    *)
      _exec_tofu "$@" || return 1
      ;;
  esac
}

create_tofu_state_s3() {
  for k in s3_bucket key
  do
    v="TOFU_STATE_${k^^}"
    test -n "${!v}" && continue
    error "Tofu couldn't init. Please define: $v"
    return 1
  done
  >/dev/null aws s3 ls "s3://${TOFU_STATE_S3_BUCKET}" && return 0
  >/dev/null aws s3 mb "s3://${TOFU_STATE_S3_BUCKET}"
}


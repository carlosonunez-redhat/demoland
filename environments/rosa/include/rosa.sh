export OCM_CONFIG="$(_get_file_from_secrets_dir 'ocm/ocm.json')"

_exec_rosa() {
  rosa login --client-id "$ROSA_CLIENT_ID" \
    --client-secret="$ROSA_CLIENT_SECRET" || return 1
  rosa "$@"
}

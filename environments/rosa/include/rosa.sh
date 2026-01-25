export OCM_CONFIG="$(_get_file_from_secrets_dir 'ocm/ocm.json')"

_exec_rosa() {
  rosa login --client-id "$ROSA_CLIENT_ID" \
    --client-secret="$ROSA_CLIENT_SECRET" || return 1
  rosa "$@"
}

_rosa_cluster_name() {
  _get_from_config '.deploy.cluster_config.name'
}

_rosa_network_stack() {
  echo "$(_rosa_cluster_name)-network"
}

_network_deployed() {
  local status
  status=$(2>/dev/null aws cloudformation describe-stacks --stack-name "$(_rosa_network_stack)" --output json | jq -r '.Stacks[0].StackStatus')
  test -n "$status" && test "${status,,}" == create_complete
}

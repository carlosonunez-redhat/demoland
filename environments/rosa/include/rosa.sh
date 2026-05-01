export OCM_CONFIG="$(_get_file_from_secrets_dir 'ocm/ocm.json')"

_rosa() {
  # There's no way to change the logging level that's shown.
  # https://github.com/openshift/rosa/blob/master/pkg/reporter/reporter.go#L114
  result=$(2>&1 rosa "$@")
  rc="$?"
  echo "$result"| grep -Ev '^WARN:|^INFO: Logged in as.*' | cat
  test "$rc" -ne 0 && error "rosa CLI command failed. Output: $result"
  return "$rc"
}

_exec_rosa() {
  export $(log_into_aws)
  client_id=$(_get_from_config '.deploy.rosa_config.auth.client_id')
  client_secret=$(_get_from_config '.deploy.rosa_config.auth.client_secret')
  token=$(_get_from_config '.deploy.rosa_config.auth.token')
  if test -n "$client_id" && test -n "$client_secret"
  then >&2 _rosa login --client-id="$client_id" --client-secret="$client_secret" || return 1
  else >&2 _rosa login --token="$token" || return 1
  fi
  _rosa "$@"
}

_rosa_cluster_type_disabled() {
  k="ROSA_DISABLE_CLUSTER_TYPE_${1^^}"
  test -n "${!k}"
}

_rosa_cluster_name() {
  _get_from_config '.deploy.cluster_config.name'
}

_rosa_cluster_api_url() {
  _exec_rosa describe cluster -c "$(_rosa_cluster_name)-$1" -o json |
    jq -r '.api.url'
}

_rosa_cluster_console_url() {
  _rosa_cluster_type_disabled "$1" && return 0

  _exec_rosa describe cluster -c "$(_rosa_cluster_name)-$1" -o json |
    jq -r '.console.url'
}

_rosa_network_stack() {
  echo "$(_rosa_cluster_name)-network-$1"
}

_rosa_oidc_id() {
  _exec_aws iam list-open-id-connect-providers |
    grep openshiftapps |
    cat |
    head -1 |
    awk -F'/' '{print $NF}' |
    tr -d '"'
}

_rosa_installer_role_arn() {
  local type
  type="$1"
  prefix="$(_rosa_cluster_name)-Installer-Role"
  test "${type,,}" == 'hcp' && prefix="$(_rosa_cluster_name)-HCP-ROSA-Installer-Role"
  _exec_aws iam list-roles --output text |
    grep "$prefix" |
    cat |
    head -1 |
    cut -f2
}

_network_deployed() {
  local status
  status=$(2>/dev/null _exec_aws cloudformation describe-stacks --stack-name "$(_rosa_network_stack "$1")" --output json | jq -r '.Stacks[0].StackStatus')
  test -n "$status" && test "${status,,}" == create_complete
}

_network_being_destroyed() {
  local status
  status=$(2>/dev/null _exec_aws cloudformation describe-stacks --stack-name "$(_rosa_network_stack "$1")" --output json | jq -r '.Stacks[0].StackStatus')
  test -n "$status" && test "${status,,}" == delete_in_progress
}

_oidc_config_created() {
  test -n "$(_rosa_oidc_id)"
}

_operator_roles_created() {
  local type
  type="${1?Please provide an operator role (classic, hcp)}"
  roles=$(_exec_aws iam list-roles |
    grep "$(_rosa_cluster_name)-${type}" |
    cat |
    cut -f2)
  test "$(wc -l <<< "$roles")" -gt 1
}

_all_clusters() {
  local type
  type="${1?Please provide an operator role (classic, hcp)}"
  _exec_rosa list clusters | grep "$(_rosa_cluster_name)-${type}"
}

_cluster_created() {
  _all_clusters "$1" | grep -q ready
}

_cluster_pending() {
  _all_clusters "$1" | grep -Eq 'pending|installing'
}

_cluster_uninstalling() {
  _all_clusters "$1" | grep -Eq uninstalling
}

_cluster_logs() {
  local type
  type="${1?Please provide an operator role (classic, hcp)}"
  _exec_rosa logs install -c "$(_rosa_cluster_name)-${type}"
}

_wait_for_cluster_created() {
  attempts=0
  max_attempts=1200
  while test "$attempts" -lt "$max_attempts"
  do
    _cluster_created "$1" && return 0

    info "[${attempts}/${max_attempts}] Waiting for cluster type '$1' to be created.."
    sleep 1
    attempts=$((attempts+1))
  done

  error "Cluster type '$1' failed to become ready; status and logs below"
  _all_clusters "$1"
  _cluster_logs "$1"
  return 1
}

_wait_for_cluster_deleted() {
  attempts=0
  max_attempts=1200
  while test "$attempts" -lt "$max_attempts"
  do
    _all_clusters "$1" >/dev/null || return 0

    if ! _cluster_uninstalling "$1"
    then
      error "Cluster type '$1' is in an unknown state; see below. Manual deletion might be required"
      _all_clusters "$1"
      return 1
    fi

    info "[${attempts}/${max_attempts}] Waiting for cluster type '$1' to be deleted.."
    sleep 1
    attempts=$((attempts+1))
  done

  error "Cluster type '$1' failed to delete; see below. Manual deletion might be required."
  _all_clusters "$1"
  return 1
}

_deploy_network() {
  _network_deployed "$1" && return 0

  info "Deploying ROSA network for cluster $(_rosa_cluster_name) (type: $1)"
  _exec_rosa create network \
    --param Region=$AWS_DEFAULT_REGION \
    --param AvailabilityZoneCount="$(_get_from_config '.deploy.cloud_config.aws.networking.availability_zones')" \
    --param VpcCidr="$(_get_from_config ".deploy.cloud_config.aws.networking.cidr_block.${1,,}")" \
    --param Name="$(_rosa_network_stack "$1")"
}

_destroy_network() {
  _network_deployed "$1" || return 0

  if ! _network_being_destroyed "$1"
  then
    info "Destroying ROSA network for cluster $(_rosa_cluster_name) (type: $1)"
    if ! _exec_aws cloudformation delete-stack --stack-name "$(_rosa_network_stack "$1")"
    then
      error "Failed to delete ROSA network CFn stack '$(_rosa_network_stack "$1")'; delete manually"
      return 1
    fi
  fi
  status=""
  attempts=0
  max_attempts=300
  while test "$attempts" -lt "$max_attempts"
  do
    if ! _network_deployed "$1" && ! _network_being_destroyed "$1"
    then return 0
    fi

    status=$(_exec_aws cloudformation describe-stacks --stack-name "$(_rosa_network_stack "$1")" --output json | jq '.Stacks[0].StackStatus')
    info "[${attempts}/${max_attempts}] Deleting '$(_rosa_network_stack "$1")', status: $status"
    attempts=$((attempts+1))
  done
}

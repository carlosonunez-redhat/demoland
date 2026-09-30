_ocm() {
  # There's no way to change the logging level that's shown.
  # https://github.com/openshift/ocm/blob/master/pkg/reporter/reporter.go#L114
  debug "Running ocm command: 'ocm $*'"
  result=$(2>&1 ocm "$@")
  rc="$?"
  messages=$(echo "$result"| grep -Ev '^WARN: The current version.*|^INFO: Logged in as.*|.*It is recommended.*' | cat)
  test -n "$messages" && info "Messages from the ocm CLI: $messages"
  return "$rc"
}

_exec_ocm() {
  token=$(_get_secret 'ocm-token')
  test -z "$token" && return 1
  >&2 _ocm login --token="$token" || return 1
  _ocm "$@"
}



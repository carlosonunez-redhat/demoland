_bastion_connected_hostname() {
  echo "bastion.$(_get_from_config '.deploy.cloud_config.aws.networking.connected.dns.domain_name')"
}

_bastion_disconnected_hostname() {
  echo "bastion.$(_get_from_config '.deploy.cloud_config.aws.networking.disconnected.dns.domain_name')"
}

_bastion_user() {
  cat "$(_get_file_from_secrets_dir 'ssh-user-bastion')"
}

_ssh() {
  ssh -i "$(_get_file_from_secrets_dir 'ssh-key')" \
    -o LogLevel=quiet \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=false \
    "$@"
}

exec_in_connected_network() {
  info "Executing in connected network through '$(_bastion_connected_hostname)': $*"
  _ssh "$(_bastion_user)@$(_bastion_connected_hostname)" "$@"
}

exec_in_disconnected_network() {
  info "Executing in disconnected network through '$(_bastion_disconnected_hostname)': $*"
  _ssh -o ProxyCommand="ssh -i $(_get_file_from_secrets_dir 'ssh-key') -W %h:%p \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    $(_bastion_user)@$(_bastion_connected_hostname)" \
    "$(_bastion_user)@$(_bastion_disconnected_hostname)" \
    "$@"
}


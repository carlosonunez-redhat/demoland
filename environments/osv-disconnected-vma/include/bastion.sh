# shellcheck shell=bash
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
  ssh -A -i "$(_get_file_from_secrets_dir 'ssh-key')" \
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
    -o LogLevel=quiet \
    $(_bastion_user)@$(_bastion_connected_hostname)" \
    "$(_bastion_user)@$(_bastion_disconnected_hostname)" \
    "$@"
}

exec_in_disconnected_node() {
  local host
  host="$1"
  exec_in_disconnected_network "ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=quiet \
    -i /home/$(_bastion_user)/.ssh/id_rsa \
    $host -- \
    '${*:2}'"  
}

rsync_into_disconnected_network() {
  local src dest
  src="$1"
  dest="$2"
  exec_in_disconnected_network "test -f $dest" && return 0
  exec_in_connected_network rsync \
    -e "'ssh -i /home/$(_bastion_user)/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" \
    -azv \
    "$src" \
      "$(_bastion_user)@$(_bastion_disconnected_hostname):$dest"
}

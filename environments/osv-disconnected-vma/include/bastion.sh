_bastion_connected_hostname() {
  echo "bastion.$(_get_from_config '.deploy.cloud_config.aws.networking.connected.dns.domain_name')"
}

_bastion_disconnected_hostname() {
  echo "bastion.$(_get_from_config '.deploy.cloud_config.aws.networking.disconnected.dns.domain_name')"
}

exec_in_public_network() {
  info "Executing in connected network through '$(_bastion_connected_hostname)': $*"
  ssh -i "$(_get_file_from_secrets_dir 'ssh-key')"  "ec2-user@$(_bastion_connected_hostname)" "$@"
}

exec_in_disconnected_network() {
  info "Executing in disconnected network through '$(_bastion_disconnected_hostname)': $*"
  ssh -i "$(_get_file_from_secrets_dir 'ssh-key')" \
    -J "ec2-user@$(_bastion_connected_hostname)" \
    "ec2-user@$(_bastion_disconnected_hostname)" \
    "$@"
}


exec_in_public_network() {
  domain_name_public=$(_get_from_config '.deploy.cloud_config.aws.networking.public.dns.domain_name')
  ssh -i "$(_get_file_from_secrets_dir 'ssh-key')"  "ec2-user@bastion.$domain_name_public" "$@"
}

exec_in_disconnected_network() {
  domain_name_public=$(_get_from_config '.deploy.cloud_config.aws.networking.public.dns.domain_name')
  domain_name_disconnected=$(_get_from_config '.deploy.cloud_config.aws.networking.private.dns.domain_name')
  ssh -i "$(_get_file_from_secrets_dir 'ssh-key')" \
    -J "ec2-user@bastion.$domain_name_public" \
    "ec2-user@bastion.$domain_name_disconnected" \
    "$@"
}


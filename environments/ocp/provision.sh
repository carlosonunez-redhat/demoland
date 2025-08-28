#!/usr/bin/env bash
set -e
source "$(dirname "$0")/../include/helpers/aws.sh"
source "$(dirname "$0")/../include/helpers/config.sh"
source "$(dirname "$0")/../include/helpers/data.sh"
source "$(dirname "$0")/../include/helpers/logging.sh"

_rhcos_ami_id_in_default_region() {
  f="$(_get_file_from_data_dir 'rhcos_ami_id_in_default_region')"
  test -f "$f" || curl -sS -Lo "$f" \
      "https://raw.githubusercontent.com/openshift/openshift-docs/refs/heads/main/modules/installation-aws-user-infra-rhcos-ami.adoc"

  range='/x86_64/,/aarch64/'
  uname -p | grep -Eiq 'aarch|arm' && range='/aarch64/,/endif/'
  awk "$range" "$f" |
    grep -A 1 "$AWS_DEFAULT_REGION" |
    tail -1 |
    sed -E 's/.*(ami-.*)`/\1/'
}

confirm_ssh_key_in_config() {
  for key in name data
  do
    k=".deploy.secrets.ssh_key.${key}"
    if test -z "$(_get_from_config "$k")"
    then
      error "'$k' not defined in config."
      exit 1
    fi
  done
}

create_ssh_key() {
  f="$(_get_file_from_data_dir 'id_rsa')"
  test -f "$f" && test "$(stat -c %a "$f")" -eq 600 && return 0

  info "Creating an SSH key for the nodes"
  _get_from_config 'deploy.secrets.ssh_key.data' > "$f"
  chmod 600 "$f"
}

load_keys_into_ssh_agent() {
  info "Starting SSH agent and loading keys"
  eval "$(ssh-agent -s)" &>/dev/null
  >&2 ssh-add -q "$(_get_file_from_data_dir 'id_rsa')"
}

upload_key_into_ec2() {
  info "Creating AWS EC2 key pair from SSH private key"
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  test -n "$(aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  pubkey="$(ssh-keygen -yf "$(_get_file_from_data_dir 'id_rsa')")"
  >/dev/null aws ec2 import-key-pair --key-name "$key_name" \
    --public-key-material "$(base64 -w 0 <<< "$pubkey")"
}

create_bootstrap_instance() {
  ami=$(_rhcos_ami_id_in_default_region)
  if test -z "$ami"
  then
    error "Couldn't find an RHCOS AMI in $AWS_DEFAULT_REGION."
    return 1
  fi
  debug "AMI: $ami"
}

export $(log_into_aws) || exit 1
confirm_ssh_key_in_config || exit 1
create_ssh_key
load_keys_into_ssh_agent
upload_key_into_ec2
create_bootstrap_instance

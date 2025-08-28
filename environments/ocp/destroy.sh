#!/usr/bin/env bash
set -e
source "$(dirname "$0")/../include/helpers/aws.sh"
source "$(dirname "$0")/../include/helpers/config.sh"
source "$(dirname "$0")/../include/helpers/data.sh"
source "$(dirname "$0")/../include/helpers/logging.sh"

delete_aws_ec2_key_pair() {a
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  test -z "$(aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  aws ec2 delete-key-pair --key-name "$key_name"
}

delete_ssh_key() {
  info "Deleting SSH key"
  rm -f "$(_get_files_from_data_dir 'id_rsa*')"
}

export $(log_into_aws) || exit 1
delete_aws_ec2_key_pair
delete_ssh_key

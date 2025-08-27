#!/usr/bin/env bash
set -e
source "$(dirname "$0")/../include/helpers/aws.sh"
source "$(dirname "$0")/../include/helpers/logging.sh"

create_ssh_key() {
  test -f /data/id_rsa && return 0

  info "Creating an SSH key for the nodes"
  ssh-keygen -q -N '' -t rsa -f /data/id_rsa
}

load_keys_into_ssh_agent() {
  info "Starting SSH agent and loading keys"
  eval "$(ssh-agent -s)" &>/dev/null
  >&2 ssh-add -q /data/id_rsa
}

eval "$(log_into_aws)" || exit 1
create_ssh_key
load_keys_into_ssh_agent

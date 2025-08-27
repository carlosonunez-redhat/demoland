#!/usr/bin/env bash
set -e
source "$(dirname "$0")/../include/helpers/logging.sh"

delete_ssh_key() {
  info "Deleting SSH key"
  rm -f /data/id_rsa*
}

stop_ssh_agent() {
  ssh-agent -k &>/dev/null
}

stop_ssh_agent
delete_ssh_key

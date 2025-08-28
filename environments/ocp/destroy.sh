#!/usr/bin/env bash
set -e
source "$(dirname "$0")/../include/helpers/logging.sh"

delete_ssh_key() {
  info "Deleting SSH key"
  rm -f /data/id_rsa*
}

delete_ssh_key

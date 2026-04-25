#!/usr/bin/env bash
# Provisions an environment!
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/gitops.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"

create_rhdh_secrets() {
  exec_oc -n rhdh get secrets -o name | grep -q 'secret/rhdh-secrets' && return 0

  info "Saving Developer Hub secrets"
  exec_oc -n rhdh create secret generic rhdh-secrets --from-file=secrets.txt="$(_get_file_from_secrets_dir 'rhdh-secrets')"
}

create_rhdh_ns() {
  exec_oc get ns -o name | grep -Eq 'namespace/rhdh' && return 0
  info "Creating Developer Hub namespace"
  exec_oc create ns rhdh
}

set -e
create_rhdh_ns
create_rhdh_secrets
setup_gitops appdev_with_vm gitops appdev-with-vm

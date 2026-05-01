#!/usr/bin/env bash
# Runs tests before deploying an environment with 'provision.sh'.
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
source "$ENVIRONMENT_INCLUDE_DIR/rosa.sh"

verify_aws_quotas() {
  info "Checking that AWS quotas are sufficient for ROSA"
  _exec_rosa verify quota
}

verify_local_environment() {
  info "Verifying that local environment is set up properly"
  _exec_rosa verify openshift-client
}

verify_credentials() {
  info "Verifying that credentials exist in environment"
  client_id=$(_get_from_config '.deploy.rosa_config.auth.client_id')
  client_secret=$(_get_from_config '.deploy.rosa_config.auth.client_id')
  token=$(_get_from_config '.deploy.rosa_config.auth.token')
  { test -n "$client_id" && test -n "$client_secret"; } && return 0
  test -n "$token" && return 0
  error "ROSA Client ID/Client Secret or token missing from config."
  return 1
}

verify_local_environment
verify_aws_quotas
verify_credentials

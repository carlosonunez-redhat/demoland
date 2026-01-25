#!/usr/bin/env bash
# Destroys resources created within this environment.
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
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"

# The 'delete' command doesn't have a 'network' subcommand, so we
# have to destroy the network "manually."
destroy_network() {
  _network_deployed || return 0

  info "Destroying ROSA network for cluster $(_rosa_cluster_name)"
  if ! aws cloudformation delete-stack --stack-name "$(_rosa_network_stack)"
  then
    error "Failed to delete ROSA network CFn stack '$(_rosa_network_name)'; delete manually"
    return 1
  fi
  status=""
  attempts=0
  max_attempts=300
  while test "$attempts" -lt "$max_attempts"
  do
    _network_deployed || return 0

    status=$(aws cloudformation describe-stacks --stack-name "$(_rosa_network_stack)" --output json | jq '.Stacks[0].StackStatus')
    info "[${attempts}/${max_attempts}] Deleting '$(_rosa_network_stack)', status: $status"
    attempts=$((attempts+1))
  done
}

destroy_network

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
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"
verify_environment_variables_defined() {
  for k in ACM_HUB_ENV_NAME ROSA_CLUSTER_ENV_NAME EKS_CLUSTER_ENV_NAME
  do
    if test -z "${!k}"
    then
      error "Base environment '$k' is not defined; please define it as an environment variable in the config"
      return 1
    fi
  done
}
verify_environment_variables_defined

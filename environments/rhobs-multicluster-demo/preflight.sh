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
source "$ENVIRONMENT_INCLUDE_DIR/helpers/rhobs.sh"
verify_environment_variables_defined() {
  for k in ACM_HUB_ENV_NAME \
           ROSA_CLUSTER_ENV_NAME \
           EKS_CLUSTER_ENV_NAME \
           RHOBS_DEMO_CLUSTER_NAME \
           RHOBS_DEMO_CLUSTER_API_FQDN
  do
    if test -z "${!k}"
    then
      error "Base environment '$k' is not defined; please define it as an environment variable in the config"
      return 1
    fi
  done
}

confirm_secrets_present() {
  for secret in pull-secret
  do
    test -n "$(_get_secret "$secret")" && continue
    error "Secret '$secret' is missing in the config. Please add it."
    return 1
  done
}

confirm_rhobs_demo_env_deployed() {
  if ! &>/dev/null exec_oc_rhobs_demo_cluster get nodes
  then
    error "Single cluster Observability demo environment '$RHOBS_DEMO_CLUSTER_NAME' not up at \
'$RHOBS_DEMO_CLUSTER_API_FQDN'. Run 'just deploy rhobs-demo' before deploying this demo."
    return 1
  fi
}

set -e
verify_environment_variables_defined
confirm_secrets_present
confirm_rhobs_demo_env_deployed

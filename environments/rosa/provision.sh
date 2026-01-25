#!/usr/bin/env bash
# Provisions an environment!
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

deploy_network() {
  _network_deployed && return 0

  info "Deploying ROSA network for cluster $(_rosa_cluster_name)"
  _exec_rosa create network \
    --param Region=$AWS_DEFAULT_REGION \
    --param AvailabilityZoneCount="$(_get_from_config '.deploy.cloud_config.aws.networking.availability_zones')" \
    --param VpcCidr="$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')" \
    --param Name="$(_rosa_network_stack)"
}

create_account_roles() {
  info "Creating AWS account roles for ROSA"
  rosa create account-roles --yes --hosted-cp --prefix="$(_rosa_cluster_name)-iam"
}

set -e
deploy_network
create_account_roles

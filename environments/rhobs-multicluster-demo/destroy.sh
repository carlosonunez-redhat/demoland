#!/usr/bin/env bash
# Destroys resources deleted within this environment.
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

delete_rhmco_s3_bucket() {
  _delete_aws_resources_from_cfn_stack_with_caps thanos_s3_bucket \
    "{}" \
    "CAPABILITY_NAMED_IAM" \
    "Deleting Thanos S3 bucket for Multi-Cluster Observability"
}

set -e
delete_rhmco_s3_bucket

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
source "$ENVIRONMENT_INCLUDE_DIR/rhobs.sh"

destroy_rhobs_s3_bucket() {
  _delete_aws_resources_from_cfn_stack loki_s3_bucket \
    "Deleting the S3 Bucket for Loki and OTel"
}

destroy_rhobs_s3_bucket || true

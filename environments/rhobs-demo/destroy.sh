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
  _exec aws s3 ls | grep -q "$(rhobs_s3_bucket)" && return 0

  info "Deleting RHOBS S3 bucket: $(rhobs_s3_bucket)"
  _exec_aws s3 rm --recursive "s3://$(rhobs_s3_bucket)/*" &&
    _exec_aws s3 rb "s3://$(rhobs_s3_bucket)"
}

destroy_rhobs_s3_bucket

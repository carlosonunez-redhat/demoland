#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/gcp.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/gitops.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
source "$ENVIRONMENT_INCLUDE_DIR/ocp.sh"

configure_gitops_admins
setup_gitops_postinstall ocp-aws-upi bootstrap bootstrap

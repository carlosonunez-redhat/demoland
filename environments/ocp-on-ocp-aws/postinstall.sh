#!/usr/bin/env bash
# Performs postinstall steps.
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/gitops.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"
setup_gitops ocp-on-ocp-aws bootstrap/operators operators
setup_gitops ocp-on-ocp-aws bootstrap/resources/base resources
info "WIP."
exit 0
wait_for_osv_to_become_ready
if ! nested_ocp_cluster_created
then
  render_install_config
  create_ocp_install_iso
  upload_ocp_install_iso_into_cluster
fi
setup_gitops ocp-on-ocp-aws bootstrap/resources/machines virtual-machines

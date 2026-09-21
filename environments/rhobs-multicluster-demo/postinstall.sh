#!/usr/bin/env bash
# Provisions an environment!
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
source "$ENVIRONMENT_INCLUDE_DIR/helpers/rhobs.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"

install_operators_into_acm_hub_cluster() {
  setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" bootstrap/operators cluster-operators
}

install_acm_into_acm_hub_cluster() {
  setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" bootstrap/resources/acm-hub acm
}

wait_for_acm_ready() {
  for pod in $(exec_oc_acm_hub -n multicluster-engine get pod -l app=console-mce -o name)
  do
    info "Waiting 180 seconds for ACM console Pod '$pod' to become ready..."
    &>/dev/null exec_oc_acm_hub wait -n multicluster-engine --for=condition=Ready --timeout=180s "$pod" && continue
    error "ACM console Pod '$pod' failed to become ready."
  done
}

set -e
install_operators_into_acm_hub_cluster
install_acm_into_acm_hub_cluster
wait_for_acm_ready
#install_acm_into_acm_hub_cluster
#import_non_hub_clusters_into_acm_hub_cluster
#wait_for_imported_clusters_to_become_ready
#install_acm_multicluster_observability_operator
#wait_for_grafana_to_become_ready

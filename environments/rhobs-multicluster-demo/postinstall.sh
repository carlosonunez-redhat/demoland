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

import_clusters_into_acm_hub_cluster() {
  for cluster in eks rosa
  do
    k="${cluster^^}_CLUSTER_ENV_NAME"
    setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" bootstrap/resources/imported-clusters/$cluster "imported-cluster-$cluster"
  done
}

wait_for_imported_cluster_namespaces_available() {
  attempts=0
  max_attempts=60
  for cluster in eks rosa
  do
    cluster_name="imported-cluster-$cluster"
    created=0
    attempts=0
    while test "$attempts" -lt "$max_attempts"
    do
      if test -n "$(exec_oc_acm_hub get ns "$cluster_name" -o name --ignore-not-found)"
      then
        created=1
        break
      fi
      info "[${attempts}/${max_attempts}] Waiting for '$cluster_name' namespace to be created..."
      attempts=$((attempts+1))
      sleep 1
    done
    test "$created" -eq 1 && continue
    error "Timed out waiting for '$cluster_name' namespace"
    return 1
  done
}

generate_kubeconfig_secrets_for_imported_clusters() {
  for cluster in eks rosa
  do
    k="${cluster^^}_CLUSTER_ENV_NAME"
    cluster_name="imported-cluster-$cluster"
    test -n "$(exec_oc_acm_hub -n "$cluster_name" get secret auto-import-secret -o name)" && continue

    kubeconfig=$(retrieve_env_kubeconfig "${!k}") || return 1
    values=(
      cluster_name "$cluster_name"
      cluster_kubeconfig_encoded "$(base64 -w 0 <<< "$kubeconfig")"
    )
    secret_file="$(mktemp "/tmp/${cluster}-kubeconfig_XXXXXXXX")"
    info "Creating import cluster secret for cluster '$cluster'"
    render_yaml_template cluster-importsecret "${values[@]}" > "$secret_file" || return 1
    exec_oc_acm_hub apply -f "$secret_file" || return 1
    rm -f "$secret_file"  || true
  done
}

set -e
install_operators_into_acm_hub_cluster
install_acm_into_acm_hub_cluster
wait_for_acm_ready
import_clusters_into_acm_hub_cluster
wait_for_imported_cluster_namespaces_available
generate_kubeconfig_secrets_for_imported_clusters
#wait_for_imported_clusters_to_become_ready
#install_acm_multicluster_observability_operator
#wait_for_grafana_to_become_ready

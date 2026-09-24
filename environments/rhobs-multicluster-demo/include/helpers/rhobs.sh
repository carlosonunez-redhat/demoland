# shellcheck shell=bash
source "$INCLUDE_DIR/helpers/ocp.sh"

exec_oc_acm_hub() {
  exec_oc_by_environment_name "$ACM_HUB_ENV_NAME" "$@"
}

exec_oc_rosa_cluster() {
  exec_oc_by_environment_name "$ROSA_CLUSTER_ENV_NAME" "$@"
}

exec_oc_eks_cluster() {
  exec_oc_by_environment_name "$EKS_CLUSTER_ENV_NAME" "$@"
}

exec_oc_rhobs_demo_cluster() {
  exec_oc_external_demo_environment "$RHOBS_DEMO_ENV_NAME" "$RHOBS_DEMO_BASE_ENV_NAME"$@"
}

imported_cluster_joined() {
  test "$(exec_oc_acm_hub get managedcluster "$1" -o yaml |
    yq -r '.status.conditions[] | select(.type == "ManagedClusterJoined") | .status' |
    grep -Ev '^null$' |
    cat)" == True
}

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

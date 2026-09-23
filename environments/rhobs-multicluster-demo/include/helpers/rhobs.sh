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

imported_cluster_joined() {
  test "$(exec_oc_acm_hub get managedcluster "$1" -o yaml |
    yq -r '.status.conditions[] | select(.type == "ManagedClusterJoined") | .status' |
    grep -Ev '^null$' |
    cat)" == True
}

_ecr_get_property() {
  if ! test -f "$(_get_file_from_shared_secret_dir "repositories/ecr/$EKS_CLUSTER_ENV_NAME/$1")"
  then
    error "Repository not created or not found in shared secrets dir"
    return 1
  fi
  cat "$(_get_file_from_shared_secret_dir "repositories/ecr/$EKS_CLUSTER_ENV_NAME/$1")"
}

_ecr_repository() {
  _ecr_get_property uri
}

_ecr_repository_password() {
  _ecr_get_property password
}

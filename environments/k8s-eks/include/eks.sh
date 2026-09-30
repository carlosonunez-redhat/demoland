# shellcheck shell=bash

_cluster_name() {
  _get_top_level_environment_name |
    tr -dc '[:alnum:]' |
    head -c 18
}

_eks_infra_name() {
  printf '%s-%s' \
    "$(_cluster_name)" \
    "$(_get_this_environment_id | tr -dc '[:alnum:]')" | head -c 27
}

_eks_version() {
  _get_from_config '.deploy.cluster_config.eks_version' |
    grep -Eo '^[0-9]+\.[0-9]+'
}

_eks_optimized_ami() {
  local arch version ssm_path
  arch="$1"
  version="$(_eks_version)"
  case "${arch,,}" in
    arm*|aarch*)
      ssm_path="/aws/service/eks/optimized-ami/${version}/amazon-linux-2023/arm64/standard/recommended/image_id"
      ;;
    *)
      ssm_path="/aws/service/eks/optimized-ami/${version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
      ;;
  esac
  _exec_aws ssm get-parameter \
    --name "$ssm_path" \
    --query 'Parameter.Value' \
    --output text
}

_eks_kubeconfig_path() {
  _get_file_from_data_dir 'eks-kubeconfig'
}


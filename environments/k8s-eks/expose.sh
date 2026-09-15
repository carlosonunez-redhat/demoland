#!/usr/bin/env bash
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/eks.sh"

expose_eks_kubeconfig() {
  local kubeconfig
  kubeconfig="$(_eks_kubeconfig_path)"
  if ! test -f "$kubeconfig"
  then
    error "Kubeconfig not found at '$kubeconfig'; has provision.sh run?"
    return 1
  fi
  expose_kubeconfig "$(cat "$kubeconfig")"
}

expose_eks_kubeconfig

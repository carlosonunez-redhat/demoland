#!/usr/bin/env bash
set -e

source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
source "$ENVIRONMENT_INCLUDE_DIR/ocp.sh"

expose_cluster_kubeconfig() {
  f="$(_get_file_from_shared_secret_dir "kubeconfigs/ocp-aws")"
  d="$(dirname "$f")"
  test "$f" && return 0
  info "Exposing cluster kubeconfig"
  test -d "$d" || mkdir -p "$d"
  cp "$(_get_file_from_data_dir "openshift-install/auth/kubeconfig")" "$f"
}

expose_cluster_kubeconfig

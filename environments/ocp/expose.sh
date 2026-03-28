#!/usr/bin/env bash
set -e

source "../../include/helpers/aws.sh"
source "../../include/helpers/config.sh"
source "../../include/helpers/data.sh"
source "../../include/helpers/errors.sh"
source "../../include/helpers/logging.sh"
source "../../include/helpers/install_config.sh"
source "../../include/helpers/yaml.sh"
source "./include/aws.sh"
source "./include/ocp.sh"

expose_cluster_kubeconfig() {
  f="$(_get_file_from_shared_secret_dir "kubeconfigs/ocp-aws")"
  d="$(dirname "$f")"
  test "$f" && return 0
  info "Exposing cluster kubeconfig"
  test -d "$d" || mkdir -p "$d"
  cp "$(_get_file_from_data_dir "openshift-install/auth/kubeconfig")" "$f"
}

expose_cluster_kubeconfig

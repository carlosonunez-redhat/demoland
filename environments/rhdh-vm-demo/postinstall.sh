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

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"
deploy_extra_workers_if_secret_defined() {
  _coreos_ami_id_for_worker() {
    local region
    region="$(_get_secret "rhdh-demo/extra-worker" | yq -r '.region')"
    images=$(exec_oc_postinstall get configmap coreos-bootimages -n openshift-machine-config-operator \
      -o jsonpath='{.data.stream}')
    echo "$images" | jq -r ".architectures.x86_64.images.aws.regions.${region}.image"
  }

  >/dev/null get_secret_quiet 'rhdh-demo/extra-worker' || return 0
  info "Creating extra workers GitOps application"
  modifications="$(cat <<-EOF
- file: bootstrap/cluster-config/extra-workers/kustomization.yaml
  shell_variables:
    CLUSTER_ID: "$(_cluster_infra_name)"
    AMI_ID: "$(_coreos_ami_id_for_worker)"
    REGION: "$(_get_secret "rhdh-demo/extra-worker" | yq -r '.region')"
    AZ: "$(_get_secret "rhdh-demo/extra-worker" | yq -r '.az')"
EOF
)"
  patches=$(render_kustomization_patches "$modifications")
  replacements="$patches"
  if test "$replacements" -gt 0
  then
    replacements_text=replacements
    test "$replacements" -eq 1 && replacements_text=replacement
    info "$replacements kustomization $replacements_text made. Commit first then perform post-install again."
    exit 0
  fi
  setup_gitops rhdh-vm-demo bootstrap/extra-workers extra-workers
}

deploy_extra_workers_if_secret_defined

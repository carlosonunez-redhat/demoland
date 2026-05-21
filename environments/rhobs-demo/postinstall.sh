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
source "$ENVIRONMENT_INCLUDE_DIR/rhobs.sh"

create_rhobs_s3_bucket() {
  params=(
    ClusterId "$(_cluster_infra_name)"
    BucketName "$(rhobs_s3_bucket)"
  )
  params_json="$(_create_aws_cf_params_json "${params[@]}")"
  _create_aws_resources_from_cfn_stack_with_caps loki_s3_bucket \
    "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating Loki S3 bucket"
}

apply_secrets() {
  _apply_grafana_secret() {
    cat >/tmp/kustomization.yaml <<-EOF
resources:
- ../components/secret-templates/resources/grafana-secret/s3
patches:
  - target:
      kind: Secret
      name: replace-me
      namespace: replace-me
    patch: |-
      - op: replace
        path: /metadata/name
        value: "$1"
      - op: replace
        path: /metadata/namespace
        value: "$2"
      - op: replace
        path: /stringData/bucketnames
        value: "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'BucketName')"
      - op: replace
        path: /stringData/region
        value: us-east-2
      - op: replace
        path: /stringData/endpoint
        value: https://s3.us-east-2.amazonaws.com
      - op: replace
        path: /stringData/access_key_id
        value: "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'AccessKey')"
      - op: replace
        path: /stringData/access_key_secret
        value: "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'SecretAccessKey')"
EOF
    exec_oc apply -k /tmp
  }
  _apply_grafana_secret rhobs-secret-s3 openshift-observability
  _apply_grafana_secret logging-loki-s3 openshift-logging
}

replace_route_hostnames() {
  local replacements
  replacements=0
  while read -r file
  do
    replacements=$((replacements+1))
    info "Replacing hostname placeholder in Kustomization: $file"
    sed -i "s/\$HOSTNAME/$(cluster_fqdn)/g" "$file"
  done < <(grep -lr "\$HOSTNAME" "$(_get_environment_dir)/bootstrap")
  echo "$replacements"
}

wait_for_observability_installer_to_be_created() {
  attempts=0
  max_attempts=180
  while test "$attempts" -lt "$max_attempts"
  do
    test -n "$(exec_oc get observabilityinstaller rhobs -n openshift-observability -o name)" && return 0
    attempts=$((attempts+1))
    info "Waiting for 'rhobs' ObservabilityInstaller to be created (make sure to commit and push changes first if needed) [attempt $attempts of $max_attempts]"
    sleep 1
  done
  return 1
}

patch_observability_installer_with_access_key() {
  info "Patching 'rhobs' ObservabilityInstaller with AWS access key"
  patch=$(printf '[{"op":"replace","path":"/spec/capabilities/tracing/storage/objectStorage/s3/accessKeyID","value":"%s"}]' \
    "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'BucketName')" \
    "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'AccessKey')")
  exec_oc patch -n openshift-observability observabilityinstaller rhobs --type=json --patch="$patch"
}

wait_for_ns() {
  info "Waiting 180s for openshift-observability namespace to be created"
  attempts=0
  max_attempts=180
  while test "$attempts" -lt "$max_attempts"
  do
      exec_oc get ns -o name | grep -q openshift-observability && return 0
      attempts=$((attempts+1))
      sleep 1
  done
  return 1
}

set -e
create_rhobs_s3_bucket
default_sc="$(exec_oc get sc -o yaml |
  yq -r '.items[] | select(.metadata.annotations | to_entries[] | .key | contains("is-default-class")) | .metadata.name')"
modifications="$(cat <<-EOF
- file: bootstrap/resources/rhobs/observability-installer/kustomization.yaml
  variables:
    region: "$(_aws_default_region)"
    bucket: "$(rhobs_s3_bucket)"
    endpoint: "https://s3.$(_aws_default_region).amazonaws.com"
- file: bootstrap/resources/rhobs/cluster-logging/kustomization.yaml
  variables:
    storageClassName: "$default_sc"
    region: "$(_aws_default_region)"
    bucket: "$(rhobs_s3_bucket)"
    endpoint: "https://s3.$(_aws_default_region).amazonaws.com"
EOF
)"
patches=$(render_kustomization_patches "$modifications")
route_replacements=$(replace_route_hostnames)
replacements="$((patches+route_replacements))"
if test "$replacements" -gt 0
then
  replacements_text=replacements
  test "$replacements" -eq 1 && replacements_text=replacement
  info "$replacements kustomization $replacements_text made. Commit first then perform post-install again."
  exit 0
fi
setup_gitops rhobs-demo bootstrap/operators bootstrap-rhobs-demo-operators
setup_gitops rhobs-demo bootstrap/resources/rhobs rh-observability
setup_gitops rhobs-demo bootstrap/resources/kafka kafka-cluster
setup_gitops rhobs-demo bootstrap/resources/cluster-config cluster-config
setup_gitops rhobs-demo bootstrap/apps cluster-apps
wait_for_ns
apply_secrets
wait_for_observability_installer_to_be_created
patch_observability_installer_with_access_key

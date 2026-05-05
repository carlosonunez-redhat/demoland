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
  _exec_aws s3 ls | grep -q "$(rhobs_s3_bucket)" && return 0

  info "Creating RHOBS S3 bucket: $(rhobs_s3_bucket)"
  _exec_aws s3 mb "s3://$(rhobs_s3_bucket)"
}

apply_secrets() {
  _apply_grafana_secret() {
    cat >/tmp/kustomization.yaml <<-EOF
  resources:
  - ../components/$2/resources/$3
  patches:
    - target:
        kind: Secret
        name: rhobs-secret
        namespace: "$2"
      patch: |-
        - op: replace
          path: /metadata/name
          value: "$1"
        - op: replace
          path: /stringData/bucketnames
          value: 3qqaxq4w-rhobs-s3-bucket
        - op: replace
          path: /stringData/region
          value: us-east-2
        - op: replace
          path: /stringData/endpoint
          value: https://s3.us-east-2.amazonaws.com
        - op: replace
          path: /stringData/access_key_id
          value: "$(_get_secret 'rhobs/s3_bucket_ak')"
        - op: replace
          path: /stringData/access_key_secret
          value: "$(_get_secret "rhobs/s3_bucket_sk")"
EOF
    exec_oc apply -k /tmp
  }
  _apply_grafana_secret rhobs-secret-s3 openshift-observability secret/s3
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
    "$(_get_secret 'rhobs/s3_bucket_ak')")
  exec_oc patch -n openshift-observability observabilityinstaller rhobs --type=json --patch="$patch"
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
replacements=$(render_kustomization_patches "$modifications")
if test "$replacements" -gt 0
then
  info "$replacements kustomization replacements made. Commit first then perform post-install again."
  exit 0
fi
apply_secrets
setup_gitops rhobs-demo bootstrap/operators bootstrap-rhobs-demo-operators
setup_gitops rhobs-demo bootstrap/resources/rhobs rh-observability
setup_gitops rhobs-demo bootstrap/resources/kafka kafka-cluster
wait_for_observability_installer_to_be_created
patch_observability_installer_with_access_key

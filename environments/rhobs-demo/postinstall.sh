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
  _create_aws_resources_from_cfn_stack_with_caps loki_s3_bucket \
    "{}" \
    "CAPABILITY_NAMED_IAM" \
    "Creating Loki S3 bucket"
}

apply_secrets() {
  _apply_tempo_secret() {
    cat >/tmp/kustomization.yaml <<-EOF
resources:
- ../components/openshift-tracing/resources/tempo-stack/secret/s3
patches:
  - target:
      kind: Secret
      name: tempostack-s3
      namespace: openshift-tracing
    patch: |-
      - op: replace
        path: /metadata/name
        value: "$1"
      - op: replace
        path: /metadata/namespace
        value: "$2"
      - op: replace
        path: /stringData/bucket
        value: "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'BucketName')"
      - op: replace
        path: /stringData/endpoint
        value: https://s3.$(_aws_region).amazonaws.com
      - op: replace
        path: /stringData/access_key_id
        value: "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'AccessKey')"
      - op: replace
        path: /stringData/access_key_secret
        value: "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'SecretAccessKey')"
EOF
    exec_oc apply -k /tmp
  }
  _apply_lokistack_secret() {
    cat >/tmp/kustomization.yaml <<-EOF
resources:
- ../components/openshift-logging/resources/loki-stack/secret/s3
patches:
  - target:
      kind: Secret
      name: logging-loki-s3
      namespace: openshift-logging
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
        path: /stringData/endpoint
        value: https://s3.$(_aws_region).amazonaws.com
      - op: replace
        path: /stringData/region
        value: $(_aws_region)
      - op: replace
        path: /stringData/access_key_id
        value: "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'AccessKey')"
      - op: replace
        path: /stringData/access_key_secret
        value: "$(_get_param_from_aws_cfn_stack loki_s3_bucket 'SecretAccessKey')"
EOF
    exec_oc apply -k /tmp
  }
  _apply_tempo_secret rhobs-secret-s3 openshift-observability
  _apply_lokistack_secret logging-loki-s3 openshift-logging
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

install_lightspeed() {
  setup_gitops rhobs-demo bootstrap/resources/lightspeed lightspeed
}

create_lightspeed_secret_gcp_vertex() {
  secret=lightspeed-secret
  ns=openshift-lightspeed
  test -n "$(exec_oc get secret -n "$ns" "$secret" -o name --ignore-not-found)" &&
    return 0

  gcp_service_account_json="$(_get_secret lightspeed-config-vertex |
    yq_strip_null -o=j -I=0 -r .credentials)"
  if test -z "$gcp_service_account_json"
  then
    error "GCP Service Account not found in config"
    return 1
  fi
  info "Creating Lightspeed Secret"
  values=(
    secret_name gcp-credentials
    gcp_service_account_json "$(base64 -w 0 <<< "$gcp_service_account_json")"
  )
  secret_file="$(mktemp "/tmp/ls_XXXXXXXX")"
  render_yaml_template lightspeed-secret-vertex "${values[@]}" | sed 's/null/""/g' > "$secret_file" || return 1
  exec_oc apply -f "$secret_file" || return 1
}

wait_for_lightspeed_ready() {
  ns="openshift-lightspeed"
  attempts=0
  pods=""
  while test "$attempts" -lt 60
  do
    pods=$(exec_oc -n "$ns" get pod -o name)
    test -n "$pods" && break
    info "[${attempts}/60] Waiting for Lightspeed Pods to be created..."
    sleep 0.5
    attempts=$((attempts+1))
  done
  if test -z "$pods"
  then
    error "Observability Pods never started."
    return 1
  fi
  for pod in $pods
  do
    info "Waiting 180 seconds for Lightspeed Pod '$pod' to become ready..."
    &>/dev/null exec_oc wait -n "$ns" --for=condition=Ready --timeout=180s "$pod" && continue
    error "Lightspeed Pod '$pod' failed to become ready."
  done
}

patch_lightspeed_config() {
  config_data=$(_get_secret "lightspeed-config-$LLM_SERVICE") || return 1
  render_kustomization_patches "$(cat <<-EOF || return 1
- file: ./bootstrap/resources/lightspeed/kustomization.yaml
  variables:
    defaultModel: "$(yq_strip_null -r '.model' <<< "$config_data")"
    'models/0/name': "$(yq_strip_null -r '.model' <<< "$config_data")"
    projectID: "$(yq_strip_null -r '.projectID' <<< "$config_data")"
    location: "$(yq_strip_null -r '.location' <<< "$config_data")"
EOF
)"
}

install_cluster_health_analyzer_mcp_server() {
  for m in 01_service_account 02_deployment 03_mcp_service
  do exec_oc apply -f "https://raw.githubusercontent.com/openshift/cluster-health-analyzer/refs/heads/mcp-dev-preview/manifests/mcp/${m}.yaml"
  done
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
- file: bootstrap/apps/simple-load-tester/kustomization.yaml
  target:
    kind: BuildConfig
    name: simple-web-server
  variables:
    ref: "$(_get_secret 'gitops/branch')"
- file: bootstrap/apps/simple-load-tester/kustomization.yaml
  variables:
    host: "web-server.$(cluster_fqdn)"
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
install_lightspeed
create_lightspeed_secret_gcp_vertex
patches=$(patch_lightspeed_config)
if test "$patches" -ge 1
then
  info "Lightspeed config patched. Please commit and push your changes, then run this step again"
  exit 0
fi
wait_for_lightspeed_ready
install_cluster_health_analyzer_mcp_server

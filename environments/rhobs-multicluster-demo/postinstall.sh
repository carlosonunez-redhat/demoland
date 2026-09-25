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
source "$ENVIRONMENT_INCLUDE_DIR/helpers/rhobs.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"
install_operators_into_acm_hub_cluster() {
  setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" bootstrap/operators cluster-operators
}

install_acm_into_acm_hub_cluster() {
  setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" bootstrap/resources/acm-hub acm
}

wait_for_acm_ready() {
  pods=""
  while test "$attempts" -lt 60
  do
    pods=$(exec_oc_acm_hub -n multicluster-engine get pod -l app=console-mce -o name)
    test -n "$pods" && break
    info "[${attempts}/60] Waiting for ACM Pods to be created..."
    sleep 0.5
    attempts=$((attempts+1))
  done
  if test -z "$pods"
  then
    error "ACM never started."
    return 1
  fi
  for pod in $pods
  do
    info "Waiting 180 seconds for ACM console Pod '$pod' to become ready..."
    &>/dev/null exec_oc_acm_hub wait -n multicluster-engine --for=condition=Ready --timeout=180s "$pod" && continue
    error "ACM console Pod '$pod' failed to become ready."
  done
}

generate_acm_pull_secret() {
  test -n "$(exec_oc_acm_hub get secret -n advanced-cluster-management-mce rh-pull-secret -o name --ignore-not-found)" && return 0

  if test -z "$(_get_file_from_secrets_dir pull-secret)"
  then
    error "pull-secret demoland secret not in config"
    return 1
  fi

  info "Creating pull secret for non-OpenShift clusters"
  exec_oc_acm_hub create secret -n advanced-cluster-management-mce generic rh-pull-secret \
    --from-literal=.dockerconfigjson="$(_get_secret pull-secret | yq_strip_null -o=j -I=0)" \
    --type=kubernetes.io/dockerconfigjson

}
import_clusters_into_acm_hub_cluster() {
  setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" bootstrap/resources/clustersets managed-cluster-sets
  while read -r cluster
  do setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" \
    "bootstrap/resources/imported-clusters/$cluster" \
    "imported-cluster-$cluster"
  done < <(find "$ENVIRONMENT_DIR/bootstrap/resources/imported-clusters" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
}

wait_for_imported_cluster_namespaces_available() {
  attempts=0
  max_attempts=60
  while read -r cluster
  do
    cluster_name="imported-cluster-$cluster"
    created=0
    attempts=0
    while test "$attempts" -lt "$max_attempts"
    do
      if test -n "$(exec_oc_acm_hub get ns "$cluster_name" -o name --ignore-not-found)"
      then
        created=1
        break
      fi
      info "[${attempts}/${max_attempts}] Waiting for '$cluster_name' namespace to be created..."
      attempts=$((attempts+1))
      sleep 1
    done
    test "$created" -eq 1 && continue
    error "Timed out waiting for '$cluster_name' namespace"
    return 1
  done < <(find "$ENVIRONMENT_DIR/bootstrap/resources/imported-clusters" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
}

_generate_auto_import_secret() {
  local cluster_name kubeconfig
  cluster_name="$1"
  imported_cluster_joined "$cluster_name" && return 0

  if test -n "$2" && test -z "$3"
  then
    error "Need to specify Kubernetes API FQDN for external env '$2'"
    return 1
  fi
  test -n "$(exec_oc_acm_hub -n "$cluster_name" get secret auto-import-secret -o name --ignore-not-found)" && return 0
  if test "$2" == external
  then kubeconfig=$(print_external_demo_env_kubeconfig "${cluster_name//imported-cluster-/}" "$3")
  else kubeconfig=$(print_env_kubeconfig "${cluster_name//imported-cluster-/}") || return 1
  fi
  values=(
    cluster_name "$cluster_name"
    cluster_kubeconfig_encoded "$(base64 -w 0 <<< "$kubeconfig")"
  )
  secret_file="$(mktemp "/tmp/${cluster}-kubeconfig_XXXXXXXX")"
  info "Creating import cluster secret for cluster '${cluster_name//imported-cluster-/}'"
  render_yaml_template cluster-importsecret "${values[@]}" > "$secret_file" || return 1
  exec_oc_acm_hub apply -f "$secret_file" || return 1
  rm -f "$secret_file"  || true
}

_generate_auto_import_secret_external_demo_environment() {
  _generate_auto_import_secret "$1" external "$2"
}

generate_auto_import_secret_for_rosa_cluster() {
  _generate_auto_import_secret imported-cluster-rosa
}

generate_auto_import_secret_for_rhobs_demo_cluster() {
  _generate_auto_import_secret_external_demo_environment imported-cluster-rhobsdemo "$RHOBS_DEMO_CLUSTER_API_FQDN"
}

# Non-OpenShift clusters don't have registry.redhat.io pull secrets; as a result
# they cannot be auto-imported
finish_importing_eks_cluster() {
  cluster_name="imported-cluster-eks"
  imported_cluster_joined "$cluster_name" && return 0

  for t in crds import
  do
    tmpfile=$(mktemp /tmp/eks-${t}-XXXXXXX.yaml)
    path="{.data.${t}\\.yaml}"
    info "Installing Klusterlet '$t' resources into EKS cluster"
    exec_oc_acm_hub get secret ${cluster_name}-import \
      -n ${cluster_name} \
      -o jsonpath="$path" | base64 --decode > "$tmpfile" &&
      exec_oc_eks_cluster apply -f "$tmpfile" || return 1
    rm -f "$tmpfile"
  done
}

patch_image_pull_secret() {
  want=$(_get_secret pull-secret | yq_strip_null -o=j -I=0)
  got=$(exec_oc_acm_hub get secret -n advanced-cluster-management image-pull-secret \
    --ignore-not-found \
    -o jsonpath='{.data.\.dockerconfigjson}')
  test "$want" == "$got" && return 0

  info "Creating image pull secret for ACM"
  exec_oc_acm_hub create secret generic image-pull-secret \
    -n advanced-cluster-management \
    --from-literal=.dockerconfigjson="$(_get_secret pull-secret | yq_strip_null -o=j -I=0)" \
    --type=kubernetes.io/dockerconfigjson || true
}

create_rhmco_s3_bucket() {
  _create_aws_resources_from_cfn_stack_with_caps thanos_s3_bucket \
    "{}" \
    "CAPABILITY_NAMED_IAM" \
    "Creating Thanos S3 bucket for Multi-Cluster Observability"
}

create_rhmco_thanos_secret() {
  test -n "$(exec_oc_acm_hub get secret \
    -n open-cluster-management-observability \
    thanos-object-storage -o name --ignore-not-found)" && return 0

  values=(
    bucket "$(_get_param_from_aws_cfn_stack thanos_s3_bucket 'BucketName')"
    endpoint "s3.$(_aws_region).amazonaws.com"
    access_key_id "$(_get_param_from_aws_cfn_stack thanos_s3_bucket 'AccessKey')"
    secret_access_key "$(_get_param_from_aws_cfn_stack thanos_s3_bucket 'SecretAccessKey')"
  )
  secret_file="$(mktemp "/tmp/mco-kubeconfig_XXXXXXXX")"
  info "Creating Thanos storage secret"
  render_yaml_template thanos-config-secret "${values[@]}" > "$secret_file" || return 1
  exec_oc_acm_hub apply -f "$secret_file" || return 1
}

create_rhmco_pull_secret() {
  secret=multiclusterhub-operator-pull-secret
  ns=open-cluster-management-observability
  test -n "$(exec_oc_acm_hub get secret -n "$ns" "$secret" -o name --ignore-not-found)" &&
    return 0

  info "Creating Observability Endpoint pull secret"
  exec_oc_acm_hub create secret generic "$secret" -n "$ns"  \
    --from-literal=.dockerconfigjson="$(_get_secret pull-secret | yq_strip_null -o=j -I=0)" \
    --type=kubernetes.io/dockerconfigjson || true
}

create_lightspeed_secret_gcp_vertex() {
  secret=lightspeed-secret
  ns=openshift-lightspeed
  test -n "$(exec_oc_acm_hub get secret -n "$ns" "$secret" -o name --ignore-not-found)" &&
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
  exec_oc_acm_hub apply -f "$secret_file" || return 1
}


install_rhmco() {
  setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" \
    bootstrap/resources/observability  \
    multicuster-observability
}

install_lightspeed() {
  setup_gitops_into_base_environment "$ACM_HUB_ENV_NAME" \
    bootstrap/resources/lightspeed  \
    lightspeed
}

wait_for_rhmco_ns() {
  attempts=0
  ns="open-cluster-management-observability"
  while test "$attempts" -lt 60
  do
    test -n "$(exec_oc_acm_hub get ns "$ns" -o name --ignore-not-found)" && return 0
    attempts="$((attempts+1))"
    info "[${attempts}/60] Waiting for Observability namespace to come up"
    sleep 0.5
  done
  error "Observability namespace never became available"
  return 1
}

wait_for_rhmco_ready() {
  ns="open-cluster-management-observability"
  attempts=0
  pods=""
  while test "$attempts" -lt 60
  do
    pods=$(exec_oc_acm_hub -n "$ns" get pod -o name | grep -E 'alertmanager|observatorium|grafana|thanos-query-frontend')
    test -n "$pods" && break
    info "[${attempts}/60] Waiting for Observability Pods to be created..."
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
    info "Waiting 180 seconds for ACM console Pod '$pod' to become ready..."
    &>/dev/null exec_oc_acm_hub wait -n "$ns" --for=condition=Ready --timeout=180s "$pod" && continue
    error "ACM console Pod '$pod' failed to become ready."
  done
}

# It can take a while for the addon-controller to ManifestWork everything that the cluster
# needs for observability to run (Secrets can take an especially long time, especially after
# failed installation attempts). Give it a LONG time for everything to get deployed.
wait_for_rhmco_ready_eks() {
  info "Waiting 10 minutes for the Observability Controller to become ready on EKS"
  exec_oc_acm_hub wait -n imported-cluster-eks \
    --for jsonpath='{.status.conditions[?(@.type=="Available")].status}=True' \
    mca observability-controller --timeout=600s
}

wait_for_lightspeed_ready() {
  ns="openshift-lightspeed"
  attempts=0
  pods=""
  while test "$attempts" -lt 60
  do
    pods=$(exec_oc_acm_hub -n "$ns" get pod -o name)
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
    &>/dev/null exec_oc_acm_hub wait -n "$ns" --for=condition=Ready --timeout=180s "$pod" && continue
    error "Lightspeed Pod '$pod' failed to become ready."
  done
}

build_and_push_test_app_images() {
  _ecr_repo() {
    cat "$(_get_file_from_shared_secret_dir "$(_aws_ecr_repository "example-apps/$1" "$EKS_CLUSTER_ENV_NAME")")"
  }

  _ecr_repo_password() {
    cat "$(_get_file_from_shared_secret_dir "$(_aws_ecr_repository_password "example-apps/$1" "$EKS_CLUSTER_ENV_NAME")")"
  }

  _log_into_ecr_repo() {
    repo_uri=$(_ecr_repo "$1") || return 1
    repo_pw=$(_ecr_repo_password "$1") || return 1
    echo "$repo_pw" |
      $CONTAINER_BIN login -u AWS --password-stdin "$repo_uri"
  }
  _build_and_push_into_ecr_repo() {
    local app
    app="$1"
    app_ctx="/apps/example-apps/$app/src"
    if ! test -d "$app_ctx"
    then
      error "Example app '$app' doesn't exist at '$app_ctx'"
      return 1
    fi
    arch=$(exec_oc_eks_cluster get node -o jsonpath='{.items[0].status.nodeInfo.architecture}')
    info "Building and pushing example app '$app' into ECR (cluster arch: $arch)"
    $CONTAINER_BIN build --arch "$arch"  -t "$(_ecr_repo "$app"):latest-$arch" "$app_ctx" &&
      $CONTAINER_BIN push "$(_ecr_repo "$app"):latest-$arch"
  }
  _app_pushed() {
    arch=$(exec_oc_eks_cluster get node -o jsonpath='{.items[0].status.nodeInfo.architecture}')
    repo_name="$(cat "$(_get_file_from_shared_secret_dir "$(_aws_ecr_repository "example-apps/${1}-$arch")")" |
      sed -E 's;.*\.amazonaws\.com/;;')"
    test -n "$(2>/dev/null _exec_aws ecr list-images --repository-name "$repo_name")"
  }

  for app in simple-web-server
  do
    _app_pushed "$app" && continue

    _log_into_ecr_repo "$app"
    _build_and_push_into_ecr_repo "$app"
  done
}

deploy_test_apps_into_non_hub() {
  local kpath cmd
  kpath=""
  cmd=""
  case "${1,,}" in
    eks)
      kpath="$ENVIRONMENT_DIR/bootstrap/apps/k8s"
      cmd=exec_oc_eks_cluster
      ;;
    rosa)
      kpath="$ENVIRONMENT_DIR/bootstrap/apps/ocp"
      cmd=exec_oc_rosa_cluster
      ;;
    *)
      errmsg="Need to specify cluster type to deploy apps into"
      test -z "$1" && errmsg="Cluster type can't be empty"
      error "$errmsg"
      return 1
      ;;
  esac
  info "Deploying test apps into '$1' cluster (kpath: $kpath)..."
  "$cmd" apply -k "$kpath"
}

patch_k8s_web_server_test_app_kustomization() {
    arch=$(exec_oc_eks_cluster get node -o jsonpath='{.items[0].status.nodeInfo.architecture}')
  render_kustomization_patches "$(cat <<-EOF || return 1
- file: ./apps/web-servers/k8s/kustomization.yaml
  variables:
    image: "$(cat "$(_get_file_from_shared_secret_dir "$(_aws_ecr_repository "example-apps/simple-web-server" "$EKS_CLUSTER_ENV_NAME")")"):latest-$arch"
EOF
)"
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

# LOL.
#
# Me: Wait! Argo can deploy Helm apps! Let's add code to `include/helpers/gitops.sh` to make that
# happen!
#
# _One hour later_
#
# Me: Helm apps via Argo are finally working! But, wait, the MCP server isn't starting. Am I missing
# something?
#
# Me: The Secret created by this chart is empty. That's really odd...
#
# _15 minutes later_
#
# Me: This chart uses the `lookup` template to discover the ACM MultiClusterHub database. Can I
# validate it locally with Helm?
#
# _5 minutes later_
#
# _Discovers https://github.com/argoproj/argo-cd/issues/5202_
#
# Me: WHY CAN'T ANYTHING EVER JUST BE EASY?!??!?
#
# ----
#
# Anyway, here's the code that you'll need to swap the below with once Argo gains
# support for `lookup`:
#
#
#
#  setup_helm_into_base_environment "$ACM_HUB_ENV_NAME" \
#    acm-mcp-server \
#    "https://raw.githubusercontent.com/stolostron/search-mcp-server/main/charts" \
#    '0.1.0' \
#    main \
#    acm-search
deploy_acm_mcp_server_into_acm_hub() {
  test -n "$(exec_helm_acm_hub ls -n openshift-mcp-servers -q)" && return 0

  info "Installing the ACM MCP server"
  test -z "$(exec_oc_acm_hub get ns openshift-mcp-servers -o name --ignore-not-found)"  &&
    test -n "$(exec_oc_acm_hub create ns openshift-mcp-servers)"
  exec_helm_acm_hub upgrade --install \
    acm-mcp-server \
    "https://raw.githubusercontent.com/stolostron/search-mcp-server/refs/heads/main/charts/acm-mcp-server-0.1.0.tgz" \
    -n openshift-mcp-servers
}


set -e
create_rhmco_s3_bucket
install_operators_into_acm_hub_cluster
install_acm_into_acm_hub_cluster
wait_for_acm_ready
generate_acm_pull_secret
import_clusters_into_acm_hub_cluster
wait_for_imported_cluster_namespaces_available
generate_auto_import_secret_for_rosa_cluster
generate_auto_import_secret_for_rhobs_demo_cluster
patch_image_pull_secret
finish_importing_eks_cluster
install_rhmco
wait_for_rhmco_ns
create_rhmco_thanos_secret
create_rhmco_pull_secret
create_lightspeed_secret_gcp_vertex
wait_for_rhmco_ready
wait_for_rhmco_ready_eks
patches=$(patch_k8s_web_server_test_app_kustomization)
if test "$patches" -ge 1
then
  info "Web server app configuration updated. Please commit and push your changes, then run this step again"
  exit 0
fi
patches=$(patch_lightspeed_config)
if test "$patches" -ge 1
then
  info "Lightspeed config patched. Please commit and push your changes, then run this step again"
  exit 0
fi
install_lightspeed
wait_for_lightspeed_ready
build_and_push_test_app_images
deploy_acm_mcp_server_into_acm_hub
deploy_test_apps_into_non_hub rosa
deploy_test_apps_into_non_hub eks

# shellcheck shell=bash
_rhcos_ami_id() {
  local arch res
  case "${1,,}" in
    arm*)
      arch=aarch64
      ;;
    amd*|x86*)
      arch=x86_64
      ;;
  esac
  region="$(_get_from_config '.deploy.cloud_config.aws.networking.region')"
  q=$(printf '.architectures.%s.images.aws.regions."%s".image' "$arch" "$region")
  res=$(openshift-install coreos print-stream-json  | jq -r "$q" | grep -iv null | cat)
  test -z "$res" && warning "No CoreOS AMI found for architecture '$arch'!!!!!!"
  echo "$res"
}

_exec_openshift_install_aws() {
  dir=$(_openshift_install_dir)
  test -d "$dir" || mkdir -p "$dir"
  region="$(_get_from_config '.deploy.cloud_config.aws.networking.region')"
  cluster_user_ak=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack cluster_user AccessKey)" \
    "Access key not found for cluster user.") || return 1
  cluster_user_sk=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack cluster_user SecretAccessKey)" \
    "Secret access key not found for cluster user.") || return 1
  AWS_ACCESS_KEY_ID="$cluster_user_ak" \
    AWS_SECRET_ACCESS_KEY="$cluster_user_sk" \
    AWS_DEFAULT_REGION="$region" \
    AWS_SESSION_TOKEN="" \
    openshift-install --dir "$dir" "$@"
}

_cluster_router_fqdn() {
  attempts=0
  max_attempts=180
  while test "$attempts" -lt "$max_attempts"
  do
    exec_oc_postinstall get service -n openshift-ingress router-default \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && return 0
    attempts=$((attempts+1))
    info "Trying to get OpenShift router load balancer (Attempt $attempts/$max_attempts)"
    sleep 1
  done
  return 1
}

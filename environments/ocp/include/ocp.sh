_rhcos_ami_id() {
  f="$(_get_file_from_data_dir 'rhcos_ami_id')"
  region="$(_get_from_config '.deploy.cloud_config.aws.networking.region')"
  test -f "$f" || curl -sS -Lo "$f" \
    "https://raw.githubusercontent.com/openshift/openshift-docs/refs/heads/enterprise-4.19/modules/installation-aws-user-infra-rhcos-ami.adoc"

  range='/x86_64/,/aarch64/'
  uname -p | grep -Eiq 'aarch|arm' && range='/aarch64/,/endif/'
  awk "$range" "$f" |
    grep -A 1 "$region" |
    tail -1 |
    sed -E 's/.*(ami-.*)`/\1/'
}

_exec_openshift_install_aws() {
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
    openshift-install "$@"
}

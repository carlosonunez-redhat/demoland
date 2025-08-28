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


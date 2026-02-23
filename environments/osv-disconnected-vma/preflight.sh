#!/usr/bin/env bash
# Runs tests before deploying an environment with 'provision.sh'.
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "../../include/helpers/aws.sh"
source "../../include/helpers/config.sh"
source "../../include/helpers/data.sh"
source "../../include/helpers/errors.sh"
source "../../include/helpers/logging.sh"
source "../../include/helpers/install_config.sh"
source "../../include/helpers/yaml.sh"

# If this environment has includes of its own, use the ./include environment
# variable, like shown in the comment below.
#
source "./include/tofu.sh"

verify_config_keys() {
  local k
  for k in '.deploy.cluster_config.cluster_name' \
    '.deploy.cluster_config.cluster_version' \
    '.deploy.cloud_config.aws.networking.connected.dns.domain_name' \
    '.deploy.cloud_config.aws.networking.disconnected.dns.domain_name' \
    '.deploy.registry_config.artifactory.jcr_version' \
    '.deploy.registry_config.artifactory.repository_name' \
    '.deploy.registry_config.artifactory.password'
  do
    test -n "$(_get_from_config "$k")" && continue
    error "Key not defined in config; please define it: $k"
    return 1
  done
}

verify_secrets() {
  local f
  for f in 'ssh-key' 'ssh-user-bastion' 'artifactory-license' 'public-pull-secret'
  do
    test -f "$(_get_file_from_secrets_dir "$f")" && continue
    error "Secret not found; please ensure it exists in config: $f"
    return 1
  done
}

set -e
verify_config_keys
verify_secrets
create_tofu_state_s3
tofu preflight

#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
pf_log() {
  eval "$1 '[PREFLIGHT] $2'"
}

confirm_route_53_public_zone_available() {
  domain_name=$(_get_from_config '.deploy.cloud_config.aws.networking.dns.domain_name')
  pf_log info "Checking that Route53 hosted zone for domain $domain_name is available."
  test -n "$(_hosted_zone_id)" && return 0
  pf_log error "Hosted zone not available for domain '$domain_name'"
  return 1
}


confirm_config_is_correct() {
  pf_log info "Checking environment config"
  for key in 'cloud_config.aws.networking.dns.domain_name' \
    'cloud_config.aws.networking.region' \
    'cloud_config.aws.networking.cidr_block' \
    'cloud_config.aws.networking.availability_zones.bootstrap' \
    'cloud_config.aws.networking.availability_zones.control_plane' \
    'cloud_config.aws.networking.availability_zones.workers' \
    'cloud_config.aws.cloudformation.stack_name' \
    'secrets.ssh_key.name' \
    'secrets.ssh_key.data' \
    'cluster_config.names.cluster' \
    'cluster_config.names.infrastructure' \
    'node_config.common.ignition_file_s3_bucket' \
    'node_config.common.pull_secret' \
    'node_config.bootstrap.quantity_per_zone' \
    'node_config.control_plane.quantity_per_zone' \
    'node_config.workers.quantity_per_zone' \
    'node_config.bootstrap.instance_type' \
    'node_config.control_plane.instance_type' \
    'node_config.workers.instance_type'
  do
    test -n "$(_get_from_config ".deploy.${key}")" && continue
    error "Key not defined in config: .deploy.${key}"
    exit 1
  done
}

# won't export correctly if quoted
# shellcheck disable=SC2046
export $(log_into_aws) || exit 1
confirm_config_is_correct
confirm_route_53_public_zone_available

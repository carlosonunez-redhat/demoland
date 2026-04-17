#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
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
    'secrets.ssh_key.name' \
    'secrets.ssh_key.data' \
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

confirm_cluster_name_matches_regex() {
  local regex
  regex='[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*'
  pf_log info "Checking that cluster name is valid: $(_cluster_name) [infra name: $(_cluster_infra_name)]"
  grep -Eq "^$regex$" <<< "$(_cluster_name)" && return 0

  error "Cluster name isn't valid: $(_cluster_name) (name must conform to regex '$regex'"
  return 1
}

confirm_more_than_two_workers_if_greater_than_zero() {
  pf_log info "Checking that more than two workers have been requested (if greater than zero)"
  num_workers="$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')"
  { test "$num_workers" -eq 0 || test "$num_workers" -ge 2; } && return 0
  error "You requested a single worker. Single worker clusters are unsupported by this environment.

Set '.deploy.node_config.workers.quantity_per_zone' to more than two and try again.

If you REALLY want a single-worker cluster, set '.deploy.node_config.workers.quantity_per_zone' to \
zero, then, in your environment, add a MachineSet with a single replica in it"
  return 1
}

# won't export correctly if quoted
# shellcheck disable=SC2046
export $(log_into_aws) || exit 1
confirm_config_is_correct
confirm_route_53_public_zone_available
confirm_cluster_name_matches_regex
confirm_more_than_two_workers_if_greater_than_zero

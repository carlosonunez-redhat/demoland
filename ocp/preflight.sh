#!/usr/bin/env bash
source "$(dirname "$0")/../include/helpers/logging.sh"

pf_log() {
  eval "$1 '[PREFLIGHT] $2'"
}

confirm_route_53_public_zone_available() {
  pf_log info "Checking that at least one public Route53 hosted zone is available."
  test -n "$(aws route53 list-hosted-zones |
    jq -r '.HostedZones[].Name' |
    grep -v null)"
}

confirm_route_53_public_zone_available

#!/usr/bin/env bash
# Provisions an environment!
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/gitops.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"

create_rhdh_secrets() {
  exec_oc -n rhdh get secrets -o name | grep -q 'secret/rhdh-secrets' && return 0

  info "Saving Developer Hub secrets"
  literals=()
  while read -r kvp
  do
    k=$(cut -f1 -d '=' <<< "$kvp")
    v=$(cut -f2 -d '=' <<< "$kvp")
    literals+=("--from-literal=$k=$v")
  done < <(_get_secret 'rhdh-secrets' | grep -v '_base64=')
  set -x
  exec_oc -n rhdh create secret generic rhdh-secrets "${literals[@]}"
  while read -r kvp
  do
    k=$(cut -f1 -d '=' <<< "$kvp" | sed -E 's/_base64$//')
    v=$(cut -f2 -d '=' <<< "$kvp")
    patch="$(printf '[{"op":"add","path":"/data/%s","value":"%s"}]' \
      "$k" "$v")"
    exec_oc -n rhdh patch secret rhdh-secrets --type json \
      --patch "$patch"
  done < <(_get_secret 'rhdh-secrets' | grep '_base64=')
}

create_rhdh_ns() {
  exec_oc get ns -o name | grep -Eq 'namespace/rhdh' && return 0
  info "Creating Developer Hub namespace"
  exec_oc create ns rhdh
}

wait_for_backstage_accessible() {
  attempts=0
  max_attempts=600
  while test "$attempts" -lt "$max_attempts"
  do
    bs_name=$(yq -r '.patches[] | select(.patch | contains("/metadata/name")) | .patch' \
        "$(dirname "$0")/gitops/resources/kustomization.yaml" |
      grep 'value:' |
      cut -f2 -d':' |
      tr -d ' ')
    bs_route=$(exec_oc get route -n rhdh "backstage-${bs_name}" -o jsonpath='{.status.ingress[0].host}' || true)
    if test -n "$bs_route"
    then
      want_code=200
      got_code="$(curl -sS -o /dev/null -w '%{http_code}' -kL "https://$bs_route")"
      test "$want_code" == "$got_code" && return 0
    fi
    info "[${attempts}/${max_attempts}] Waiting for Backstage to become available (fqdn: $bs_route, want_code: $want_code, got_code: $got_code)"
    attempts=$((attempts+1))
    sleep 1
  done
}

set -e
create_rhdh_ns
create_rhdh_secrets
for dir in operators resources
do setup_gitops appdev_with_vm "gitops/$dir" "appdev-with-vm-$dir"
done
wait_for_backstage_accessible

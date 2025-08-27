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

confirm_iam_user_has_correct_permissions() {
  pf_log info "Confirming that this IAM user has correct permission set."
  _get_aws_policy_source_arn() {
    grep -q 'user/' <<< "$1" && { echo "$1"; return 0; }
    if grep -q 'assumed-role/' <<< "$1"
    then
      role_name=$(sed -E 's/.*assumed-role/assumed-role/' <<< "$1" | cut -f2 -d '/')
      aws iam get-role --role-name "$role_name" | jq -r '.Role.Arn'
      return 0
    fi
    pf_log error "Can't evaluate the IAM policy ARN to use (received: $1)"
    return 1
  }
  _get_required_iam_permissions_from_config() {
    yq -r '.iam.permissions.required[]|"\"" + . + "\""' "$(dirname "$0")/config.yaml" |
      tr '\n' ' ' | sort -u
  }
  _get_optional_iam_permissions_from_config() {
    yq -r '.iam.permissions.optional[]|"\"" + . + "\""' "$(dirname "$0")/config.yaml" |
      tr '\n' ' ' | sort -u
  }
  local role_name
  this_arn=$(aws sts get-caller-identity | jq -r '.Arn')
  if test -z "$this_arn"
  then
    pf_log error "Couldn't get current AWS user."
    return 1
  fi
  policy_source_arn=$(_get_aws_policy_source_arn "$this_arn") || return 1
  for t in required optional
  do
    # quoting it adds an unbalanced single quote for some reason.
    # shellcheck disable=SC2046
    result=$(aws iam simulate-principal-policy --policy-source-arn "$policy_source_arn" \
      --action-names $(eval "_get_${t}_iam_permissions_from_config")) 
    if test -z "$result"
    then
      pf_log error "couldn't test ${t} IAM permissions"
      return 1
    fi
    denied=$(echo "$result" |
      yq -r '.EvaluationResults[] | select(.EvalDecision != "allowed") | .EvalActionName')
    test -z "$denied" && continue
    if test "$t" == required
    then
      pf_log error "IAM account is missing these permissions: $denied"
      return 1
    else pf_log warning "IAM account is missing these permissions: $denied"
    fi
  done
}

confirm_route_53_public_zone_available
confirm_iam_user_has_correct_permissions

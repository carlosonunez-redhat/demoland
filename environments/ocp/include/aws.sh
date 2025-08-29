# shellcheck shell=bash
_hosted_zone_id() {
  domain_name=$(_get_from_config '.deploy.cloud_config.aws.networking.dns.domain_name')
  aws route53 list-hosted-zones |
    jq --arg name "$domain_name" -r '.HostedZones[] | select(.Name == $name + ".") | .Id' |
    grep -v null |
    cat
}

_hosted_zone_name() {
  domain_name=$(_get_from_config '.deploy.cloud_config.aws.networking.dns.domain_name')
  aws route53 list-hosted-zones |
    jq --arg name "$domain_name" -r '.HostedZones[] | select(.Name == $name + ".") | .Name' |
    grep -v null |
    sed -E 's/\.$//' | cat
}

_all_availability_zones() {
  local az
  az=""
  for t in bootstrap control_plane workers
  do az="${az}$(_get_from_config ".deploy.cloud_config.aws.networking.availability_zones.${t}[]")\n"
  done
  echo -e "$az" | grep -Ev '^$' | sort -u
}

_get_param_from_aws_cfn_stack() {
  local stack_name param
  stack_name="$1"
  param="$2"
  resolved_stack_name="$(_aws_cf_stack_name "$1")"
  results=$(aws cloudformation describe-stacks --stack-name "$resolved_stack_name" |
    jq -r '.Stacks[0]' |
    grep -v null |
    cat)
  if test -z "$results"
  then
    error "Stack does not exist: $resolved_stack_name"
    return 1
  fi
  stack_state=$(jq -r '.StackStatus' <<< "$result")
  if ! grep -Eiq '^(create|update)_complete$' <<< "$stack_state"
  then
    error "Can't get params right now; stack '$resolved_stack_name' is in state '$stack_state'"
    return 1
  fi
  echo "$result" | jq --arg k "$param" -r '.Outputs[] | select(.OutputKey == $k) | .OutputValue' |
    grep -v null |
    cat
}

_cfn_list_param() {
  printf '[%s]' "$1"
}

_create_aws_cf_params_json() {
  local json
  json=''
  while test "$#" -ne 0
  do
    key="$1"
    val="$2"
    obj=$(printf '{"ParameterKey":"%s","ParameterValue":"%s"}'  "$key" "$val")
    json="${json},${obj}"
    shift
    shift
  done
  printf "[%s]" "$(sed -E 's/,$// ; s/^,//' <<< "$json")"
}

_aws_cf_stack_name() {
  printf '%s-%s' \
    "$(_get_from_config '.deploy.cloud_config.aws.cloudformation.stack_name')" \
    "$1"
}

_wait_for_cf_stack_until_state() {
  _print_every_five() {
    local idx
    idx="$1"
    shift
    test "$((idx % 5))" -eq 0 && "$@"
    return 0
  }
  _aws_cfn_failure_reasons() {
    aws cloudformation describe-stack-events --stack-name "$1" |
      jq -r '.StackEvents[] |
        select(
          .ResourceStatus == "CREATE_FAILED" and
          (.ResourceStatusReason|contains("Resource creation cancelled")|not))
        | "  - " + .LogicalResourceId + ": [" + .ResourceType + "] " + .ResourceStatusReason'
  }

  local stack_name
  iterations=0
  stack_name="$(_aws_cf_stack_name "$1")"
  desired_state="${2,,}"
  in_progress_state="${3,,}"
  failed_state="${4,,}"
  while true
  do
    result=$(aws cloudformation describe-stacks --stack-name "$stack_name" |
        jq -r '.Stacks[0]')
    if test -z "$result"
    then
      if test -z "$(aws sts get-caller-identity)"
      then
        info "[iteration #${iterations}] '$stack_name': credentials expired while waiting. refreshing"
        eval $(log_into_aws) || return 1
        continue
      fi
      if grep -q 'delete' <<< "$desired_state"
      then
        info "[iteration #${iterations}] '$stack_name': $desired_state achieved!"
        return 0
      fi
    fi
    stack_state="$(jq -r '.StackStatus' <<< "$result" | tr '[:upper:]' '[:lower:]')"
    reason="$(jq -r '.StackStatusReason' <<< "$result" | grep -v null | cat)"
    if { grep -q 'create' <<< "$desired_state" && grep -q 'delete' <<< "$stack_state"; } ||
      { grep -q 'delete' <<< "$desired_state" && grep -q 'create' <<< "$stack_state"; }
    then
      error "'$stack_name': want $desired_state but stack is in conflicting state '$stack_state'"
      return 1
    fi
    case "${stack_state}" in
      "$desired_state")
        test "$iterations" != 0 &&
          info "[iteration #${iterations}] '$stack_name': ${desired_state^^} achieved!"
        return 0
        ;;
      "$in_progress_state")
        _print_every_five "$iterations" info \
          "[iteration #${iterations}] '$stack_name': ${desired_state^^} not yet achieved; in ${stack_state^^}..."
        ;;
      rollback_in_progress)
        _print_every_five "$iterations" \
          info "[iteration #${iterations}] '$stack_name': Failed; rolling back..."
        ;;
      rollback_complete)
        manual_delete_command=(aws cloudformation delete-stack
          --stack-name "$stack_name")
        error "'$stack_name' CloudFormation stack rolled back; destroy the stack and re-deploy \
or run this manually: ${manual_delete_command[*]}. Reasons why this failed:"
        while read -r line
        do error "$line"
        done < <(_aws_cfn_failure_reasons "$stack_name")
        return 1
        ;;
      "$failed_state")
        error "'$stack_name' CloudFormation stack did not achieve ${desired_state^^}: $reason"
        return 1
        ;;
    esac
    iterations=$((iterations+1))
    sleep 0.5
  done
}

_delete_aws_resources_from_cfn_stack() {
  _not_exists() {
    test -z "$(2>/dev/null aws cloudformation describe-stacks \
      --stack-name "$(_aws_cf_stack_name "$1")")"
  }
  _run() {
    local stack_file
    stack_file="$(dirname "$0")/include/cloudformation/${1}.yaml"
    if ! test -f "$stack_file"
    then
      error "Stack file not found: $stack_file"
      return 1
    fi
    aws cloudformation delete-stack --stack-name "$(_aws_cf_stack_name "$1")" >/dev/null
  }
  _wait() {
    _wait_for_cf_stack_until_state "$1" \
      'delete_complete' \
      'delete_in_progress' \
      'delete_failed'
  }
  info_msg="$3"
  test -z "$info_msg" && info_msg="Deleting resources in stack '$1'..."
  _not_exists "$1" || { info "$info_msg" &&  _run "$1" "$2"; }
  _wait  "$1"
}

_create() {
  _exists() {
    test -n "$(2>/dev/null aws cloudformation describe-stacks \
      --stack-name "$(_aws_cf_stack_name "$1")")"
  }
  _run() {
    local stack_file
    stack_file="$(dirname "$0")/include/cloudformation/${1}.yaml"
    if ! test -f "$stack_file"
    then
      error "Stack file not found: $stack_file"
      return 1
    fi
    cmd=(aws cloudformation create-stack
      --stack-name "$(_aws_cf_stack_name "$1")"
      --template-body "file://$stack_file")
    test -n "$2" && cmd+=(--parameters "$2")
    test -n "$3" && cmd+=(--capabilities "$3")
    "${cmd[@]}" >/dev/null
  }
  _wait() {
    _wait_for_cf_stack_until_state "$1" \
      'create_complete' \
      'create_in_progress' \
      'create_failed'
  }
  info_msg="$4"
  test -z "$info_msg" && info_msg="Creating resources in stack '$1'..."
  _exists "$1" || { info "$info_msg" && _run "$1" "$2" "$3"; }
  _wait "$1"
}

_create_aws_resources_from_cfn_stack() {
  _create "$1" "$2" "$3"
}

_create_aws_resources_from_cfn_stack_with_caps() {
  _create "$1" "$2" "$3" "$4"
}

# shellcheck shell=bash
source "$(dirname "$0")/../include/helpers/cloud_creds.sh"
SESSION_FILE=/data/aws_session

_exec_aws() {
  export $(log_into_aws)
  AWS_PAGER="" aws "$@"
}

_aws_region() {
  _get_cloud_cred 'aws.sts' aws_default_region || return 1
}


_aws_sts_assumerole() {
  local ak sk role_arn external_id
  ak=$(_get_cloud_cred 'aws.sts' aws_access_key_id) || return 1
  sk=$(_get_cloud_cred 'aws.sts' aws_secret_access_key) || return 1
  role_arn=$(_get_cloud_cred 'aws.sts' aws_role_arn) || return 1
  external_id=$(_get_cloud_cred 'aws.sts' aws_role_external_id) || return 1
  export AWS_ACCESS_KEY_ID="$ak"
  export AWS_SECRET_ACCESS_KEY="$sk"
  export AWS_DEFAULT_REGION="$(_aws_region)"
  export AWS_SESSION_TOKEN=""
  info "[aws] Assuming role [$role_arn] using access key [$ak]"
  AWS_PAGER="" aws sts assume-role --role-arn "$role_arn" \
    --external-id "$external_id" \
    --role-session-name "session-$(date +%s)"
}

log_into_aws() {
  if test -n "$AWS_DISABLE_STS"
  then
    ak=$(_get_cloud_cred 'aws.iam_user' aws_access_key_id)
    sk=$(_get_cloud_cred 'aws.iam_user' aws_secret_access_key)
    region=$(_get_cloud_cred 'aws.iam_user' aws_default_region)
    if test -z "$ak" || test -z "$sk"  || test -z "$region"
    then
      error "Couldn't find AWS credentials. Ensure they are defined in the \
'cloud_creds.aws.iam_user' key in your config."
      return 1
    fi
    printf "AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\nAWS_DEFAULT_REGION=%s\nAWS_REGION=%s" \
      "$ak" "$sk" "$region" "$region"
    return 0
  fi
  if test -f "$SESSION_FILE"
  then
    expiry=$(grep 'EXPIRES_ON' "$SESSION_FILE" | awk -F'=' '{print $NF}' | date -f - '+%s')
    now=$(date +%s)
    expiry_within_15m=$((expiry-(15*60)))
    if test "$now" -lt "$expiry_within_15m"
    then cat "$SESSION_FILE"; return 0
    fi
  fi
  info "Creating temporary AWS credentials."
  session_creds=$(_aws_sts_assumerole)
  if test -z "$session_creds"
  then
    error "Couldn't create an AWS STS session."
    echo "AWS_NOT_CONFIGURED=true"
    return 1
  fi
  {
    echo "AWS_DEFAULT_REGION=$(_aws_region)"; \
    jq -r '.Credentials |
      "AWS_ACCESS_KEY_ID=" + .AccessKeyId + "\n" +
      "AWS_SECRET_ACCESS_KEY=" + .SecretAccessKey + "\n" +
      "AWS_SESSION_TOKEN=" + .SessionToken + "\n" +
      "AWS_STS_EXPIRES_ON=" + .Expiration' <<< "$session_creds";
  }| tee "$SESSION_FILE"
}

_aws_default_region() {
  _exec_aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]'
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
  local stack_name stack_state param results 
  stack_name="$1"
  param="$2"
  resolved_stack_name="$(_aws_cf_stack_name "$1")"
  results=$(_exec_aws cloudformation describe-stacks --stack-name "$resolved_stack_name" |
    jq -r '.Stacks[0]' |
    grep -v null |
    cat)
  if test -z "$results"
  then
    error "Stack does not exist: $resolved_stack_name"
    return 1
  fi
  stack_state=$(jq -r '.StackStatus' <<< "$results")
  if ! grep -Eiq '^(create|update)_complete$' <<< "$stack_state"
  then
    error "Can't get params right now; stack '$resolved_stack_name' is in state '$stack_state'"
    return 1
  fi
  echo "$results" | jq --arg k "$param" -r '.Outputs[] | select(.OutputKey == $k) | .OutputValue' |
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
  printf '%s-cfn-%s' \
    "$(_get_top_level_environment_name)" \
    "$1" | tr -c '[:alnum:]' '-'
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
    _exec_aws cloudformation describe-stack-events --stack-name "$1" |
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
    result=$(_exec_aws cloudformation describe-stacks --stack-name "$stack_name" |
        jq -r '.Stacks[0]')
    if test -z "$result"
    then
      if test -z "$(_exec_aws sts get-caller-identity)"
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
      update_complete)
        info "[iteration #${iterations}] '$stack_name': Stack updated externally; skipping"; \
        return 0
        ;;
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
        manual_delete_command=(_exec_aws cloudformation delete-stack
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
    test -z "$(2>/dev/null _exec_aws cloudformation describe-stacks \
      --stack-name "$(_aws_cf_stack_name "$1")")"
  }
  _run() {
    local stack_file
    stack_file="$ENVIRONMENT_INCLUDE_DIR/cloudformation/${1}.yaml"
    if ! test -f "$stack_file"
    then
      error "Stack file not found: $stack_file"
      return 1
    fi
    _exec_aws cloudformation delete-stack --stack-name "$(_aws_cf_stack_name "$1")" >/dev/null
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

_create_cfn_stack() {
  _not_exists() {
    test -z "$(2>/dev/null _exec_aws cloudformation describe-stacks \
      --stack-name "$(_aws_cf_stack_name "$1")")"
  }
  _run() {
    local stack_file
    stack_file="$ENVIRONMENT_INCLUDE_DIR/cloudformation/${1}.yaml"
    if ! test -f "$stack_file"
    then
      error "Stack file not found: $stack_file"
      return 1
    fi
    cmd=(_exec_aws cloudformation create-stack
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
  info_msg="[$(_cluster_name)] $3"
  test "$#" -eq 4 && info_msg="[$(_cluster_name)] $4"
  test -z "$info_msg" && info_msg="Creating resources in stack '$1'..."
  if _not_exists "$1"
  then
    info "$info_msg"
    test "$#" -eq 3 && _run "$1" "$2"
    test "$#" -eq 4 && _run "$1" "$2" "$3"
  fi
  _wait "$1"
}

_create_aws_resources_from_cfn_stack() {
  _create_cfn_stack "$1" "$2" "$3"
}

_create_aws_resources_from_cfn_stack_with_caps() {
  _create_cfn_stack "$1" "$2" "$3" "$4"
}

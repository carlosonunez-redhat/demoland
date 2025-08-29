# shellcheck shell=bash
_vpc_id() {
  cidr_block=$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')
  aws ec2 describe-vpcs |
    jq --arg cidr "$cidr_block" -r '.Vpcs[] | select(.CidrBlock == $cidr) | .VpcId' |
    grep -v 'null' | cat
}

_vpc_subnet_from_cidr_block() {
  local cidr_block
  cidr_block="$1"
  aws ec2 describe-subnets |
  jq --arg vpc_id "$(_vpc_id)" --arg cidr "$subnet_cidr_block" \
    '.Subnets[] | select(.VpcId == $vpc_id and .CidrBlock == $cidr) | .SubnetId' |
  grep -v null |
  cat
}

_vpc_subnet_from_availability_zone() {
  local az
  az="$1"
  az_id="$(aws ec2 describe-availability-zones |
    jq --arg name "$az" -r '.AvailabilityZones[] | select(.ZoneName == $name) | .ZoneId' |
    grep -v null | cat)"
  aws ec2 describe-subnets |
    jq -r --arg vpc_id "$(_vpc_id)" --arg az_id "$az_id" \
      '.Subnets[] | select(.VpcId == $vpc_id and .AvailabilityZoneId == $az_id) | .SubnetId' |
      grep -v null | cat
}


_all_availability_zones() {
  local az
  az=""
  for t in bootstrap control_plane workers
  do az="${az}$(_get_from_config ".deploy.cloud_config.aws.networking.availability_zones.${t}[]")\n"
  done
  echo -e "$az" | grep -Ev '^$' | sort -u
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
    if test -z "$result" && grep 'delete' <<< "$desired_state"
    then
      info "[iteration #${iterations}] '$stack_name': $desired_state achieved!"
      return 0
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
      rollback_complete|"$failed_state")
        error "'$stack_name' CloudFormation stack did not achieve ${desired_state^^}: $reason"
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
    aws cloudformation delete-stack --stack-name "$(_aws_cf_stack_name "$1")"
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

_create_aws_resources_from_cfn_stack() {
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
    "${cmd[@]}"
  }
  _wait() {
    _wait_for_cf_stack_until_state "$1" \
      'create_complete' \
      'create_in_progress' \
      'create_failed'
  }
  info_msg="$3"
  test -z "$info_msg" && info_msg="Creating resources in stack '$1'..."
  _exists "$1" || { info "$info_msg" && _run "$1" "$2"; }
  _wait "$1"
}


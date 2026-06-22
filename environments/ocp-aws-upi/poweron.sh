#!/usr/bin/env bash
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/gcp.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
source "$ENVIRONMENT_INCLUDE_DIR/ocp.sh"

power_on_instances() {
  _exec_ec2_instance_op_and_wait() {
    local instance_id want_state change_state change_op
    instance_id="$1"
    want_state="$2"
    change_state="$3"
    change_op="$4"
    attempts=0
    max_attempts=180
    want_state="$2"
    while test "$attempts" -ne "$max_attempts"
    do
      state=$(_exec_aws ec2 describe-instances --instance-id "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' --output text)
      case "${state,,}" in
        "${change_state,,}")
          info "---> [$instance_id] Changing '$state'"
           _exec_aws ec2 "${change_op}" --instance-id "$instance_id" || return 1
           ;;
        "${want_state,,}")
          return 0
          ;;
        *)
          info "---> [$instance_id] Waiting for state '$want_state'; got '$state'"
          attempts=$((attempts+1))
          sleep 1
          ;;
      esac
    done
    return 1
  }

  _start_instance_and_wait() {
    _exec_ec2_instance_op_and_wait "$1" 'running' 'stopped' 'start-instances'
  }

  _exec_aws ec2 describe-instances \
    --query 'Reservations[].Instances[?(@.State.Name != `terminated` && @.Tags[?Key==`Name` && contains(Value, `'"$(_cluster_infra_name)"'`)])].InstanceId' \
    --output text |
    while read -r instance_id
    do _start_instance_and_wait "$instance_id"
    done
}
power_on_instances

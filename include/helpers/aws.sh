# shellcheck shell=bash
SESSION_FILE=/data/aws_session
log_into_aws() {
  for required in AWS_ROLE_ARN AWS_ROLE_EXTERNAL_ID
  do
    test -n "${!required}" && continue
    error "Please define $required in the environment"
    echo "AWS_NOT_CONFIGURED=true"
    return 1
  done
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
  session_creds=$(aws sts assume-role --role-arn "$AWS_ROLE_ARN" \
    --external-id "$AWS_ROLE_EXTERNAL_ID" \
    --role-session-name "session-$(date +%s)")
  if test -z "$session_creds"
  then
    error "Couldn't create an AWS STS session."
    echo "AWS_NOT_CONFIGURED=true"
    return 1
  fi
  jq -r '.Credentials |
    "AWS_ACCESS_KEY_ID=" + .AccessKeyId + "\n" +
    "AWS_SECRET_ACCESS_KEY=" + .SecretAccessKey + "\n" +
    "AWS_SESSION_TOKEN=" + .SessionToken + "\n" +
    "AWS_STS_EXPIRES_ON=" + .Expiration' <<< "$session_creds" | tee "$SESSION_FILE"
}

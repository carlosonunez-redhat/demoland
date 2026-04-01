# shellcheck shell=bash
source "$(dirname "$0")/../include/helpers/cloud_creds.sh"

SESSION_FILE=/data/aws_session
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
  info "[aws] Assuming role [$role_arn] using access key [$ak]"
  aws sts assume-role --role-arn "$role_arn" \
    --external-id "$external_id" \
    --role-session-name "session-$(date +%s)"
}
log_into_aws() {
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

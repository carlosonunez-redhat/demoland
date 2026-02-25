# shellcheck shell=bash
# oc-mirror can take a long time, which will greatly slow down development time while working on
# this script. Storing these images in an EBS volume that gets shared between bootstrap nodes
# (bastions) and deleted manually is much faster than storing them ephemerally and using rsync to
# transfer between them. However, managing the volume via Terraform/OpenTofu adds complexity since
# it doesn't easily support stuff that gets created once.
_wait_for_oc_mirror_volume_attachment_state() {
  local id want_attachments got_attachments attempts max_attempts
  id=$(oc_mirror_ebs_volume_id)
  attempts=0
  max_attempts=300
  want_attachments=1
  test "${1,,}" == detached && want_attachments=0
  while true
  do
    info "[oc-mirror volume] Waiting for state '$1' (attempt $attempts of $max_attempts)"
    got_attachments=$(aws ec2 describe-volumes --volume-id "$(oc_mirror_ebs_volume_id)" |
      yq -r '.Volumes[].Attachments | length')
    test "$want_attachments" -eq "$got_attachments" && return 0
    attempts=$((attempts+1))
    sleep 1
  done
}

oc_mirror_ebs_volume_id() {
  result=$(aws ec2 describe-volumes --filter 'Name=tag:oc-mirror,Values=true' |
    yq -r '.Volumes[0].VolumeId' |
    grep -Ev '^null$' |
    cat)
  if test -n "$result"
  then
    awk -F'/' '{print $NF}' <<< "$result"
    return 0
  fi
  error "oc-mirror EBS volume not found; have you run 'provision_oc_mirror_ebs_volume' yet?"
  return 1
}

oc_mirror_volume_attached() {
  local id instance_id want got
  id=$(oc_mirror_ebs_volume_id)
  instance_id="$1"
  test -z "$id" && return 1
  want=attached
  got="$(aws ec2 describe-volumes --volume-id  "$id" | \
    yq -r '.Volumes[0].Attachments[] | select(.InstanceId == "'"$instance_id"'") | .State')"
  test "$want" == "$got"
}

wait_for_oc_volume_detached() {
  _wait_for_oc_mirror_volume_attachment_state detached
}

wait_for_oc_volume_attached() {
  _wait_for_oc_mirror_volume_attachment_state attached
}

provision_oc_mirror_ebs_volume() {
  test -n "$(oc_mirror_ebs_volume_id)" && return 0

  local az
  az="$(_get_from_config '.deploy.cloud_config.aws.storage.oc_mirror.availability_zone')"
  >/dev/null aws ec2 create-volume \
    --availability-zone "$az" \
    --iops 5000 \
    --size 1000 \
    --volume-type gp3 \
    --throughput 1000 \
    --tag-specifications 'ResourceType=volume,Tags=[{Key=oc-mirror,Value=true}]'
}

detach_oc_mirror_volume_from_instance() {
  local instance_id
  instance_id="$1"
  info "Detaching oc-mirror volume '$(oc_mirror_ebs_volume_id)' from instance '$instance_id'"
  >/dev/null aws ec2 detach-volume --device /dev/sdh \
    --instance-id "$instance_id" \
    --volume-id "$(oc_mirror_ebs_volume_id)" &&
    wait_for_oc_volume_detached
}

attach_oc_mirror_volume_to_instance() {
  local instance_id
  instance_id="$1"
  info "Attaching oc-mirror volume '$(oc_mirror_ebs_volume_id)' to instance '$instance_id'"
  >/dev/null aws ec2 attach-volume --device /dev/sdh \
    --instance-id "$instance_id" \
    --volume-id "$(oc_mirror_ebs_volume_id)" &&
    wait_for_oc_volume_attached
}

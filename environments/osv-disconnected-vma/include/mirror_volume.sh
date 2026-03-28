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
  az="$(_get_from_config '.deploy.cloud_config.aws.networking.common.default_availability_zone')"
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

attach_and_mount_oc_mirror_volume() {
  _oc_mirror_device_id() {
    local res
    attempts=0
    max_attempts=60
    cmd="sudo lsblk -N | grep $(oc_mirror_ebs_volume_id | tr -d '-') | cut -f1 -d ' '"
    while true
    do
      if test "${1,,}" == connected
      then res=$(exec_in_connected_network "$cmd")
      else res=$(exec_in_disconnected_network "$cmd")
      fi
      if test -n "$res"
      then
        echo "$res"
        return 0
      fi
      info "[attach] Waiting for device to be recognized in '$1' bastion \
(attempts $attempts of $max_attempts)"
      sleep 1
      attempts=$((attempts+1))
    done
    return 1
  }

  local connected_instance_id \
    disconnected_instance_id \
    opposite_instance_id \
    instance_id dev_id \
    exec_cmd
  connected_instance_id=$(tofu output -raw connected_bastion_instance_id) || return 1
  disconnected_instance_id=$(tofu output -raw disconnected_bastion_instance_id) || return 1
  if test "${1,,}" == connected
  then
    instance_id="$connected_instance_id"
    opposite_instance_id="$disconnected_instance_id"
    exec_cmd=exec_in_connected_network
  else
    instance_id="$disconnected_instance_id"
    opposite_instance_id="$connected_instance_id"
    exec_cmd=exec_in_disconnected_network
  fi
  oc_mirror_volume_attached "$opposite_instance_id" && \
    detach_oc_mirror_volume_from_instance "$opposite_instance_id"
  if ! oc_mirror_volume_attached "$instance_id"
  then attach_oc_mirror_volume_to_instance "$instance_id" || return 1
  fi
  dev_id="$(_oc_mirror_device_id "${1,,}")" || return 1
  if test -z "$dev_id"
  then
    error "Couldn't find block device mapped to oc-mirror EBS volume"
    return 1
  fi
  "$exec_cmd" \
    'sudo lsblk -fnr /dev/'"$dev_id"' | grep -q ext4 || sudo mkfs.ext4 /dev/'"$dev_id"';'
  "$exec_cmd" 'sudo sh -c "mkdir -p /mnt/mirror && \
    { mount | grep -q '"$dev_id"' || mount -t ext4 /dev/'"$dev_id"' /mnt/mirror; } && \
    chown -R fedora /mnt/mirror"' || return 1
}

umount_and_detach_oc_mirror_volume() {
  local instance_id
  instance_id="$(tofu output -raw "${1,,}_bastion_instance_id")" || return 1
  oc_mirror_volume_attached "$instance_id" || return 0
  exec_cmd="exec_in_${1,,}_network"
  "$exec_cmd" "sudo umount /mnt/mirror" || return 1
  detach_oc_mirror_volume_from_instance "$instance_id"
}


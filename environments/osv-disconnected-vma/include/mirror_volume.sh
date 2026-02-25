# shellcheck shell=bash
oc_mirror_ebs_volume_id() {
  result=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters 'Key=oc-mirror,Values=true' | yq -r '.ResourceTagMappingList[0].ResourceARN' |
    grep -Ev '^null$' | cat)
  if test -n "$result"
  then
    awk -F'/' '{print $NF}' <<< "$result"
    return 0
  fi
  error "oc-mirror EBS volume not found; have you run 'provision_oc_mirror_ebs_volume' yet?"
  return 1
}

# oc-mirror can take a long time, which will greatly slow down development time while working on
# this script. Storing these images in an EBS volume that gets shared between bootstrap nodes
# (bastions) and deleted manually is much faster than storing them ephemerally and using rsync to
# transfer between them. However, managing the volume via Terraform/OpenTofu adds complexity since
# it doesn't easily support stuff that gets created once.
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



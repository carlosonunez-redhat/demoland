#!/usr/bin/env bash
# Provisions an environment!
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "../../include/helpers/aws.sh"
source "../../include/helpers/config.sh"
source "../../include/helpers/data.sh"
source "../../include/helpers/errors.sh"
source "../../include/helpers/logging.sh"
source "../../include/helpers/install_config.sh"
source "../../include/helpers/yaml.sh"

# If this environment has includes of its own, use the ./include environment
# variable, like shown in the comment below.
#
source "./include/bastion.sh"
source "./include/osv.sh"
source "./include/tofu.sh"

provision_base_infrastructure_and_vms() {
  exec_tofu apply
}

confirm_dns_records() {
  _verify_record() {
    2>/dev/null host "$1"
  }

  cluster_name=$(_get_from_config '.deploy.cluster_config.cluster_name')
  domain_name=$(_get_from_config '.deploy.cloud_config.aws.networking.connected.dns.domain_name')
  
  for ocp_component in apps api api-int bootstrap control-plane worker
  do
    if test "$ocp_component" == control-plane || test "$ocp_component" == worker
    then
      for i in $(seq 1 3)
      do _verify_record "${ocp_component}-${i}.${cluster_name}.${domain_name}"
      done
    else _verify_record "${ocp_component}.${cluster_name}.${domain_name}"
    fi
  done

  for ext_component in registry
  do _verify_record "${ext_component}.${domain_name}"
  done
}

confirm_public_bastion_accessible() {
  exec_in_public_network whoami
}

confirm_disconnected_bastion_accessible() {
  exec_in_disconnected_network whoami
}

set -e
provision_base_infrastructure_and_vms
confirm_public_bastion_accessible
confirm_private_bastion_accessible
#install_oc_client_into_private_bastion
#upload_rhcos_images_to_s3_bucket
#verify_rhcos_images_accessible_from_private_bastion
#generate_rhcos_ignition_files
#upload_rhcos_ignition_files_to_s3_bucket
#verify_rhcos_ignition_files_accessible_from_private_bastion
#create_bare_metal_instances
#provision_bare_metal_instances
#confirm_dns_records

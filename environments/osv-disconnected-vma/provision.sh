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

download_packages_in_connected_bastion() {
  packages="curl rsync"
  exec_in_connected_network "sudo dnf -y install $packages"
}

install_oc_client_into_disconnected_bastion() {
  local version
  version=$(_get_from_config '.deploy.cluster_config.cluster_version')
  url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$version/openshift-client-linux.tar.gz"
  exec_in_connected_network "mkdir -p /tmp/oc && \
    { test -f /tmp/oc_client.tar.gz || curl -sSL -o /tmp/oc_client.tar.gz '$url'; } &&  \
    tar -xzf /tmp/oc_client.tar.gz -C /tmp/oc"
  exec_in_connected_network "test -f /tmp/oc/oc" || return 1
  exec_in_disconnected_network 'mkdir -p $HOME/.local/bin'
  rsync_into_disconnected_network /tmp/oc/oc '$HOME/.local/bin'
  exec_in_disconnected_network 'chmod +x $HOME/.local/bin/oc && oc version --client | grep -q Client'
}

install_artifactory_on_registry_instance() {
  _artifactory_installed_and_running() {
    local want got
    want=enabled
    got=$(exec_in_disconnected_node 'fedora@registry.private.network' 'sudo systemctl is-enabled artifactory')
    test "$want" == "${got,,}"
  }

  _artifactory_installed_and_running && return 0

  local version
  version=$(_get_from_config '.deploy.registry_config.artifactory.jcr_version')
  url="https://releases.jfrog.io/artifactory/bintray-artifactory/org/artifactory/jcr/\
jfrog-artifactory-jcr/$version/jfrog-artifactory-jcr-${version}-linux.tar.gz"
  exec_in_connected_network "test -f /tmp/jcr.tar.gz || curl -sSL -o /tmp/jcr.tar.gz '$url'";
  exec_in_disconnected_node 'fedora@registry.private.network' "sudo mkdir -p /app/jfrog && sudo chown $(_bastion_user) /app/jfrog"
  rsync_into_disconnected_network /tmp/jcr.tar.gz /tmp/jcr.tar.gz
  exec_in_disconnected_network 'rsync -avrh /tmp/jcr.tar.gz fedora@registry.private.network:/app/jfrog/jcr.tar.gz'
  exec_in_disconnected_node 'fedora@registry.private.network' \
    'test -d /app/jfrog/artifactory && exit 0; \
      cd /app/jfrog; tar -xzf jcr.tar.gz ; mv artifactory* artifactory'
  exec_in_disconnected_node 'fedora@registry.private.network' \
    'cd /app/jfrog/artifactory/app/bin && sudo ./installService.sh'
  exec_in_disconnected_node 'fedora@registry.private.network' \
    'sudo /app/jfrog/artifactory/app/third-party/yq/yq -i \
      ".shared.database.allowNonPostgresql = true" \
      /app/jfrog/artifactory/var/etc/system.yaml'
  ip_address="$(exec_in_disconnected_node 'fedora@registry.private.network' 'hostname -I' |
    tr -d ' ')"
  exec_in_disconnected_node 'fedora@registry.private.network' \
    'sudo /app/jfrog/artifactory/app/third-party/yq/yq -i \
      ".shared.node.ip = \"'"$ip_address"'\"" \
      /app/jfrog/artifactory/var/etc/system.yaml'
  exec_in_disconnected_node 'fedora@registry.private.network' \
    'sudo semanage fcontext -a -t bin_t /app/jfrog && sudo chcon -R -t bin_t /app/jfrog/artifactory/app/bin'
  exec_in_disconnected_node 'fedora@registry.private.network' \
    "sudo systemctl start artifactory.service"
}

wait_for_artifactory_up() {
  exec_in_disconnected_node 'fedora@registry.private.network' \
    'timeout 300 sh -c "while true; do curl -o /dev/null -s --connect-timeout 1000 \
      localhost:8082 && break; sleep 1; done"'
}

apply_artifactory_license() {
  _license_applied() {
    exec_in_disconnected_node 'fedora@registry.private.network' \
      'sudo test -f /app/jfrog/artifactory/var/etc/artifactory/artifactory.lic'
  }

  _license_applied && return 0

  cat "$(_get_file_from_secrets_dir 'artifactory-license')" | \
    exec_in_connected_network sh -c 'cat - > /tmp/artifactory.lic'
  rsync_into_disconnected_network /tmp/artifactory.lic /tmp/artifactory.lic
  exec_in_disconnected_network 'rsync -avrh /tmp/artifactory.lic fedora@registry.private.network:/tmp/license'
  exec_in_disconnected_node 'fedora@registry.private.network' \
    'sudo cp /tmp/license /app/jfrog/artifactory/var/etc/artifactory/artifactory.lic && \
      sudo systemctl restart artifactory'
  wait_for_artifactory_up
}

change_artifactory_default_password() {
  _password_changed() {
    exec_in_disconnected_node 'fedora@registry.private.network' 'sudo test -f /app/jfrog/.passwd_changed'
  }

  _password_changed && return 0

  payload="$(printf '{\\\"password\\\": \\\"%s\\\",\\\"email\\\":\\\"%s\\\",\\\"admin\\\":true\\\"}' \
    "$(_get_from_config '.deploy.registry_config.artifactory.password')" \
    "$(_get_from_config '.deploy.registry_config.artifactory.email_address')")"
  exec_in_disconnected_node 'fedora@registry.private.network' \
    'curl -u admin:password \
      http://localhost:8082/artifactory/api/security/users/admin \
      -H "Content-Type: application/json" \
      -d "'"$payload"'" && sudo touch /app/jfrog/.passwd_changed'
}


set -e
provision_base_infrastructure_and_vms
initialize_bastions
initialize_disconnected_node 'fedora@registry.private.network'
download_packages_in_connected_bastion
install_oc_client_into_disconnected_bastion
install_artifactory_on_registry_instance
if ! wait_for_artifactory_up
then
  error "Artifactory never started (or took too long to start)"
  exit 1
fi
apply_artifactory_license
change_artifactory_default_password
#upload_rhcos_images_to_s3_bucket
#verify_rhcos_images_accessible_from_disconnected_bastion
#generate_rhcos_ignition_files
#upload_rhcos_ignition_files_to_s3_bucket
#verify_rhcos_ignition_files_accessible_from_disconnected_bastion
#create_bare_metal_instances
#provision_bare_metal_instances
#confirm_dns_records

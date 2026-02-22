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

_restart_artifactory() {
  local cmd
  cmd="sudo systemctl restart artifactory.service"
  test "${1,,}" == quiet && cmd="${cmd} --no-block"
  exec_in_disconnected_node 'fedora@registry.private.network' "$cmd"
  test "${1,,}" == quiet && return 0

  if ! exec_in_disconnected_node 'fedora@registry.private.network' \
    'timeout 300 sh -c "while true; do curl -o /dev/null -s --connect-timeout 1000 \
      localhost:8082 && break; sleep 1; done"'
  then
    error "Artifactory never started (or took too long to start)"
    exit 1
  fi
}

_restart_artifactory_no_wait() {
  _restart_artifactory quiet
}

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

install_artifactory_on_disconnected_registry_instance() {
  _artifactory_installed_and_running() {
    local want got
    want=enabled
    got=$(exec_in_disconnected_node 'fedora@registry.private.network' 'sudo systemctl is-enabled artifactory')
    test "$want" == "${got,,}" || return 1
    exec_in_disconnected_network '2>/dev/null nc -w 1 -z registry.private.network 8082'
  }

  # https://jfrog.com/help/r/jfrog-installation-setup-documentation/install-artifactory-with-linux-archive
  # However, these docs do not disambiguate Artifactory from their other
  # Artifactory-lite SKUs (JCR, X-Ray, etc.)
  _download_artifactory_archive_into_connected_bastion() {
    local version
    version=$(_get_from_config '.deploy.registry_config.artifactory.jcr_version')
    url="https://releases.jfrog.io/artifactory/artifactory-pro/org/artifactory/pro/\
jfrog-artifactory-pro/$version/jfrog-artifactory-pro-${version}-linux.tar.gz"
    exec_in_connected_network "test -f /tmp/jcr.tar.gz || curl -L -o /tmp/jcr.tar.gz '$url'";
  }

  _rsync_artifactory_archive_into_disconnected_bastion() {
    rsync_into_disconnected_network /tmp/jcr.tar.gz /tmp/jcr.tar.gz
  }

  _rsync_artifactory_archive_into_disconnected_registry_instance() {
    exec_in_disconnected_network 'rsync -avrh /tmp/jcr.tar.gz fedora@registry.private.network:/app/jfrog/jcr.tar.gz'
  }

  _create_jfrog_home_dir_in_disconnected_registry_instance() {
    exec_in_disconnected_node \
      'fedora@registry.private.network' \
      "sudo mkdir -p /app/jfrog && sudo chown $(_bastion_user) /app/jfrog"
  }

  _extract_artifactory_in_disconnected_registry_instance() {
    exec_in_disconnected_node 'fedora@registry.private.network' \
      'test -d /app/jfrog/artifactory && exit 0; \
        cd /app/jfrog; tar -xzf jcr.tar.gz ; mv artifactory* artifactory'
  }

  _install_artifactory_service() {
    exec_in_disconnected_node 'fedora@registry.private.network' \
      'cd /app/jfrog/artifactory/app/bin && sudo ./installService.sh'
    # This wasn't in the docs.
    exec_in_disconnected_node 'fedora@registry.private.network' \
      'sudo semanage fcontext -a -t bin_t /app/jfrog && sudo chcon -R -t bin_t /app/jfrog/artifactory/app/bin'
  }

  # Skip onboarding and work around some bugs in the installer.
  # "Build this Lego set. The pieces are ALL OVER THE INTERNET. Good luck." -JFrog, probably.
  _configure_artifactory() {
    local ip_address
    ip_address="$(exec_in_disconnected_node 'fedora@registry.private.network' 'hostname -I' |
      tr -d ' ')"
    # allowNonPostgresql: The ONLY config param that was documented in the installation docs
    # jfconnect.enabled = false: UI won't load if this is enabled. Don't know why.
    # (source: https://stackoverflow.com/questions/78661243/artifactory-oss-wont-start-log-shows-failed-executing-getentitlements-server)
    # ip address: Weird UI errors due to script using inet6 iface address instead of inet4.
    # (source: beer, coffee, and https://jfrog.com/help/r/artifactory-how-to-fix-invalid-url-escape-et/artifactory-how-to-fix-invalid-url-escape-et)
    for modification in ".shared.database.allowNonPostgresql = true" \
      ".shared.node.ip = \\\"$ip_address\\\"" \
      ".shared.extraJavaOpts = \\\"-Dartifactory.onboarding.skipWizard=true\\\"" \
      ".jfconnect.enabled = false"
    do exec_in_disconnected_node 'fedora@registry.private.network' \
      'sudo /app/jfrog/artifactory/app/third-party/yq/yq -i \
        "'"$modification"'" \
        /app/jfrog/artifactory/var/etc/system.yaml'
    done
  }

  _artifactory_installed_and_running && return 0

  set -e
  _create_jfrog_home_dir_in_disconnected_registry_instance
  _download_artifactory_archive_into_connected_bastion
  _rsync_artifactory_archive_into_disconnected_bastion
  _rsync_artifactory_archive_into_disconnected_registry_instance
  _extract_artifactory_in_disconnected_registry_instance
  _install_artifactory_service
  _configure_artifactory
  _restart_artifactory
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
    'sudo cp /tmp/license /app/jfrog/artifactory/var/etc/artifactory/artifactory.lic'
  _restart_artifactory
}


change_artifactory_default_password() {
  _password_changed() {
    local username password
    username=$(_get_from_config '.deploy.registry_config.artifactory.username')
    password=$(_get_from_config '.deploy.registry_config.artifactory.password')
    exec_in_disconnected_node \
      'fedora@registry.private.network' \
      "curl -s -u \"${username}:${password}\" http://localhost:8082/artifactory/api/system  | grep -q \"System Info\""
  }

  _password_changed && return 0

  local username password
  username=$(_get_from_config '.deploy.registry_config.artifactory.username')
  password=$(_get_from_config '.deploy.registry_config.artifactory.password')
  # https://jfrog.com/help/r/artifactory-how-to-create-an-admin-token-without-using-the-ui/artifactory-how-to-create-an-admin-token-without-using-the-ui
  exec_in_disconnected_node \
    'fedora@registry.private.network' \
    "sudo sh -c \"echo '${username}@*=${password}' > /app/jfrog/artifactory/var/etc/access/bootstrap.creds\"" &&
  exec_in_disconnected_node 'fedora@registry.private.network' \
    "sudo chown artifactory:artifactory /app/jfrog/artifactory/var/etc/access/bootstrap.creds" &&
  exec_in_disconnected_node 'fedora@registry.private.network' \
    "sudo chmod 600 /app/jfrog/artifactory/var/etc/access/bootstrap.creds" &&
    _restart_artifactory
}

create_artifactory_admin_token() {
  _token_created() {
    test -f "$(_get_file_from_data_dir 'artifactory_admin_token')"
  }

  _token_created && return 0
  # https://jfrog.com/help/r/artifactory-how-to-create-an-admin-token-without-using-the-ui/artifactory-how-to-create-an-admin-token-without-using-the-ui
  local token new_token_json
  exec_in_disconnected_node 'fedora@registry.private.network' \
    "sudo touch /app/jfrog/artifactory/var/bootstrap/etc/access/keys/generate.token.json" &&
    _restart_artifactory || return 1

  if ! exec_in_disconnected_node 'fedora@registry.private.network' \
    "timeout 120 sh -c \"while true; do sudo test -f /app/jfrog/artifactory/var/etc/access/keys/token.json && break; sleep 1; done\""
  then
    error "Timed out while waiting for Artifactory to generate a short-lived admin token"
    return 1
  fi
  token_json=$(exec_in_disconnected_node 'fedora@registry.private.network' \
    'sudo cat /app/jfrog/artifactory/var/etc/access/keys/token.json')
  if test -z "$token_json"
  then
    error "Artifactory failed to create a short-lived admin token."
    return 1
  fi
  token=$(echo "$token_json" | jq -r '.token')
  attempts=0
  while test "$attempts" -lt 90
  do
    new_token_json=$(exec_in_disconnected_node 'fedora@registry.private.network' \
      "curl -sS -H \"Authorization: Bearer $token\" \
        -X POST \
        http://localhost:8082/access/api/v1/tokens \
        -d \"scope=applied-permissions/user\"") || true
    test -n "$new_token_json" && break
    attempts=$((attempts+1))
  done
  access_token=$(jq -r .access_token <<< "$new_token_json")
  if test -z "$access_token" || test "${access_token,,}" == null
  then
    error "Couldn't create an admin token with Artifactory"
    return 1
  fi
  echo "$access_token" > "$(_get_file_from_data_dir 'artifactory_admin_token')"
}

create_artifactory_oci_repo() {
  _repo_created() {
    local username password want got
    username=$(_get_from_config '.deploy.registry_config.artifactory.username')
    password=$(_get_from_config '.deploy.registry_config.artifactory.password')
    want=200
    got=$(exec_in_disconnected_network "curl -sSL -o /dev/null \
      -u \"${username}:${password}\" \
      -w \"%{http_code}\" \
      http://registry.private.network:8082/artifactory/$(_get_from_config '.deploy.registry_config.artifactory.repository_name')")
    test "$want" == "$got"
  }

  _repo_created && return 0
  access_token="$(cat "$(_get_file_from_data_dir 'artifactory_admin_token')")"
  repo_config=$(cat <<-EOF
{
  "key": "$(_get_from_config '.deploy.registry_config.artifactory.repository_name')",
  "rclass": "local",
  "packageType": "docker",
  "description": "The repository."
}
EOF
)
  repo_config_json=$(jq -cr . <<< "$repo_config") || return 1
  exec_in_disconnected_network \
    "curl -sS -H \"Authorization: Bearer $access_token\" \
      -H \"Content-Type: application/json\" \
      -X PUT \
      -d '$repo_config_json' \
      http://registry.private.network:8082/artifactory/api/repositories/$(_get_from_config '.deploy.registry_config.artifactory.repository_name')"
}


set -e
provision_base_infrastructure_and_vms
initialize_bastions
initialize_disconnected_node 'fedora@registry.private.network'
download_packages_in_connected_bastion
install_oc_client_into_disconnected_bastion
install_artifactory_on_disconnected_registry_instance
apply_artifactory_license
change_artifactory_default_password
create_artifactory_admin_token
create_artifactory_oci_repo
#upload_rhcos_images_to_s3_bucket
#verify_rhcos_images_accessible_from_disconnected_bastion
#generate_rhcos_ignition_files
#upload_rhcos_ignition_files_to_s3_bucket
#verify_rhcos_ignition_files_accessible_from_disconnected_bastion
#create_bare_metal_instances
#provision_bare_metal_instances
#confirm_dns_records

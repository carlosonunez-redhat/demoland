# shellcheck shell=bash
_bastion_connected_hostname() {
  echo "bastion.$(_get_from_config '.deploy.cloud_config.aws.networking.connected.dns.domain_name')"
}

_bastion_disconnected_hostname() {
  echo "bastion.$(_get_from_config '.deploy.cloud_config.aws.networking.disconnected.dns.domain_name')"
}

_bastion_user() {
  cat "$(_get_file_from_secrets_dir 'ssh-user-bastion')"
}

_ssh() {
  ssh -i "$(_get_file_from_secrets_dir 'ssh-key')" \
    -o LogLevel=quiet \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=false \
    "$@"
}

_rsync() {
  rsync -e "ssh -i '$(_get_file_from_secrets_dir 'ssh-key')' \
    -o LogLevel=quiet \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=false" \
    "$@"
}

exec_in_connected_network() {
  info "Executing in connected network through '$(_bastion_connected_hostname)': $*"
  _ssh "$(_bastion_user)@$(_bastion_connected_hostname)" "$@"
}

exec_in_disconnected_network() {
  info "Executing in disconnected network through '$(_bastion_disconnected_hostname)': $*"
  _ssh \
    -o ProxyCommand="ssh -i $(_get_file_from_secrets_dir 'ssh-key') \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=quiet \
      -W %h:%p $(_bastion_user)@$(_bastion_connected_hostname)" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=quiet \
    "$(_bastion_user)@$(_bastion_disconnected_hostname)" \
    "$@"
}

exec_in_disconnected_node() {
  local host
  host="$1"
  exec_in_disconnected_network "ssh $host -- '${*:2}'"
}

rsync_from_connected_network() {
  local src_remote dest_local
  src_remote="$1"
  dest_local="$2"
  _rsync -azv "$(_bastion_user)@$(_bastion_connected_hostname):$src_remote" "$dest_local"
}

rsync_into_disconnected_network() {
  local src dest
  src="$1"
  dest="$2"
  exec_in_disconnected_network "test -f $dest" && return 0
  exec_in_connected_network rsync -azv "$src" \
    "$(_bastion_user)@$(_bastion_disconnected_hostname):$dest"
}

_bastion_init_file() {
  connected_id=$(tofu output -raw connected_bastion_instance_id)
  disconnected_id=$(tofu output -raw disconnected_bastion_instance_id)
  if test -n "$connected_id" && test -n "$disconnected_id"
  then
    echo "$(_get_file_from_data_dir)/.bastions_initialized_${connected_id}_${disconnected_id}"
    return 0
  fi
  error "One of these bastion instance IDs is empty: [connected: $connected_id], [disconnected: $disconnected_id]"
  return 1
}

_disconnected_node_init_file() {
  echo "$(_get_file_from_data_dir)/.disconnected_node_initialized_$(base64 -w 0 <<< "$1")"
}

_disconnected_network_ssh_config() {
  cat <<-EOF
Host *.private.network
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel quiet
  IdentityFile /home/$(_bastion_user)/.ssh/id_rsa
EOF
}

initialize_disconnected_node() {
  test -f "$(_disconnected_node_init_file "$1")" && return 0

  _disconnected_network_ssh_config | exec_in_connected_network sh -c 'cat - > /tmp/config' &&
    rsync_into_disconnected_network /tmp/config /tmp/config && 
    exec_in_disconnected_network 'cat /tmp/config | ssh -i ~/.ssh/id_rsa \
      -o StrictHostKeyChecking=no \
      -o LogLevel=quiet \
      -o UserKnownHostsFile=/dev/null '"$1"' sh -c "cat - > ~/.ssh/config"' &&
      touch "$(_disconnected_node_init_file "$1")"
}

initialize_bastions() {
  _copy_ssh_config_into_bastions() {
    _disconnected_network_ssh_config | exec_in_connected_network 'cat - > ~/.ssh/config'
    rsync_into_disconnected_network '~/.ssh/config' '~/.ssh/config'
  }
  _copy_private_key_into_bastions() {
    cat "$(_get_file_from_secrets_dir 'ssh-key')" |
      exec_in_connected_network 'cat - > ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa'
    cat "$(_get_file_from_secrets_dir 'ssh-key')" |
      exec_in_disconnected_network 'cat - > ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa'
  }
  _confirm_connected_bastion_accessible() {
    info "Waiting 300 seconds for connected bastion to become available"
    attempts=0
    while test "$attempts" -lt 300
    do
      # https://stackoverflow.com/a/71962683
      curl --telnet-option 'DISCONNECT_NOW=1' --connect-timeout 1 -s \
        "telnet://$(_bastion_connected_hostname):22"
      test "$?" -eq 48 && return 0
      attempts="$((attempts+1))"
    done
    return 1
  }
  _confirm_disconnected_bastion_accessible() {
    attempts=0
    while test "$attempts" -lt 300
    do
      # https://stackoverflow.com/a/71962683
      exec_in_connected_network "curl -s --telnet-option DISCONNECT_NOW=1 \
--connect-timeout 1 telnet://$(_bastion_disconnected_hostname):22"
      test "$?" -eq 48 && return 0
      sleep 1
      attempts="$((attempts+1))"
    done
    return 1
  }
  _mark_bastions_initialized() {
    touch "$(_bastion_init_file)" || return 1
  }
  _bastions_initialized() {
    test -f "$(_bastion_init_file)" || return 1
  }

 
  _bastions_initialized && return 0

  if ! _confirm_connected_bastion_accessible
  then
    error "Bastion in connected network is inaccessible"
    return 1
  fi
  if ! _confirm_disconnected_bastion_accessible
  then
    error "Bastion in disconnected network is inaccessible"
    return 1
  fi
  _copy_private_key_into_bastions &&
    _copy_ssh_config_into_bastions &&
    _mark_bastions_initialized

}

deinitialize_disconnected_node() {
  rm -f "$(_disconnected_node_init_file "$1")"
}

deinitialize_bastions() {
  rm -f "$(_bastion_init_file)" || return 1
}

install_into_bastions() {
  local component oc_file_to_download oc_file check_command download_stanza
  component="$1"
  oc_file_to_download="$2"
  oc_file="$3"
  check_command="$4"
  test -z "$check_command" && check_command='--help'
  version=$(_get_from_config '.deploy.cluster_config.cluster_version')
  url="https://mirror.openshift.com/pub/openshift-v4/clients/$component/$oc_file_to_download"
  download_stanza="curl -sSL -o - $url | tar -xvzf - -C \$HOME/.local/bin"
  grep -q '.tar.gz' <<< "$oc_file_to_download" ||
    download_stanza="curl -sSL -o \$HOME/.local/bin/$oc_file $url"
  exec_in_connected_network "test -f \$HOME/.local/bin/$oc_file && exit 0; \
    mkdir -p \$HOME/.local/bin && \
    $download_stanza && \
    chmod +x \$HOME/.local/bin/$oc_file && $oc_file $check_command >/dev/null"
  exec_in_disconnected_network "test -d \$HOME/.local/bin || mkdir -p \$HOME/.local/bin"
  rsync_into_disconnected_network "\$HOME/.local/bin/$oc_file" "\$HOME/.local/bin"
  exec_in_disconnected_network "chmod +x \$HOME/.local/bin/$oc_file && $oc_file $check_command >/dev/null"
}

install_ocp_tool_into_bastions() {
  version=$(_get_from_config '.deploy.cluster_config.cluster_version')
  install_into_bastions "ocp/$version" "$@"
}

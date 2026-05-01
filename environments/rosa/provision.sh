#!/usr/bin/env bash
# Provisions an environment!
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
source "$ENVIRONMENT_INCLUDE_DIR/rosa.sh"

deploy_network_classic() {
  _rosa_cluster_type_disabled classic && return 0

  _deploy_network classic
}

deploy_network_hcp() {
  _deploy_network hcp
}

create_account_roles() {
  roles=$(_exec_aws iam list-roles | grep "$(_rosa_cluster_name)" | cat)
  test "$(wc -l <<< "$roles")" -gt 1 && return 0
  info "Creating AWS account roles for ROSA"
  _exec_rosa create account-roles \
    --classic \
    --hosted-cp \
    --prefix "$(_rosa_cluster_name)" \
    --mode auto \
    --yes
}

create_oidc_configuration() {
  _oidc_config_created && return 0

  info "Creating AWS OIDC config for ROSA"
  _exec_rosa create oidc-config \
    --mode auto \
    --yes
}

create_operator_roles_classic() {
  _rosa_cluster_type_disabled classic && return 0

  _operator_roles_created classic && return 0

  info "Creating ROSA classic operator roles"
  _exec_rosa create operator-roles \
    --mode=auto \
    --prefix="$(_rosa_cluster_name)-classic" \
    --oidc-config-id="$(_rosa_oidc_id)" \
    --installer-role-arn="$(_rosa_installer_role_arn classic)"
}

create_operator_roles_hcp() {
  _operator_roles_created hcp && return 0

  info "Creating ROSA HCP operator roles"
  _exec_rosa create operator-roles \
    --mode=auto \
    --hosted-cp \
    --prefix="$(_rosa_cluster_name)-hcp" \
    --oidc-config-id="$(_rosa_oidc_id)" \
    --installer-role-arn="$(_rosa_installer_role_arn hcp)"
}

create_cluster_classic() {
  _rosa_cluster_type_disabled classic && return 0

  _cluster_created classic && return 0

  if ! _cluster_pending classic
  then
    version="$(_get_from_config 'deploy.cluster_config.openshift_version')"
    info "Creating classic ROSA cluster (OpenShift version: $version)"
    _exec_rosa create cluster \
      --yes \
      --cluster-name "$(_rosa_cluster_name)-classic" \
      --version "$version" \
      --sts \
      --mode auto \
      --oidc-config-id "$(_rosa_oidc_id)" \
      --operator-roles-prefix "$(_rosa_cluster_name)-classic" \
      --machine-cidr "$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block.classic')"
  fi

  _wait_for_cluster_created classic
}

create_cluster_hcp() {
  _cluster_created hcp && return 0

  if ! _cluster_pending hcp
  then
    subnets=$(_exec_aws ec2 describe-subnets --filters "Name=tag:Name,Values=$(_rosa_network_stack hcp)*" \
      --query 'Subnets[].SubnetId' \
      --output text | tr '\t' ',')
    if test -z "$subnets"
    then
      error "Unable to resolve ROSA subnets in VPC; see error message above for more details."
      return 1
    fi
    billing_account=$(_exec_aws sts get-caller-identity | jq -r .Account)
    version="$(_get_from_config 'deploy.cluster_config.openshift_version')"
    info "Creating HCP ROSA cluster (OpenShift version: $version)"
    _exec_rosa create cluster \
      --yes \
      --hosted-cp \
      --cluster-name "$(_rosa_cluster_name)-hcp" \
      --sts \
      --mode auto \
      --oidc-config-id "$(_rosa_oidc_id)" \
      --operator-roles-prefix "$(_rosa_cluster_name)-hcp" \
      --machine-cidr "$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block.hcp')" \
      --subnet-ids "$subnets" \
      --billing-account "$billing_account" \
      --version "$version"
  fi

  _wait_for_cluster_created hcp
}

set_up_google_idp() {
  _idp_exists() {
    _exec_rosa list idps -c "$(_rosa_cluster_name)-$1" |
      grep -q "$2"
  }
  local type
  type="$1"

  _rosa_cluster_type_disabled "$type" && return 0
  auths=$(_get_from_config '.deploy.cluster_config.cluster_auth.google_oauth.auths')
  for role in $(yq -r '.[].role' <<< "$auths" | sort -u)
  do
    { test -z "$role" || test "${role,,}" == null ; } && continue
    _idp_exists "$type" "google-${role}" && return 0
    auths=$(_get_from_config '.deploy.cluster_config.cluster_auth.google_oauth.auths')
    { test -z "$auths" || test "$auths" == '[]'; } && return 0
    details=$(_get_from_config '.deploy.cluster_config.cluster_auth.google_oauth.additional_details')
    client_id=$(yq -r '.client_id' <<< "$details")
    client_secret=$(yq -r '.client_secret' <<< "$details")
    if test -z "$client_id" || test -z "$client_secret"
    then
      error "client_id and client_secret must be defined"
      return 1
    fi
    hosted_domain=$(yq -r '.approved_domain' <<< "$details" | grep -iv null | cat)
    if test -z "$hosted_domain"
    then
      error "approved_domain must be defined."
      return 1
    fi
    auth_infos=$(yq -o=j -I=0 -r '[.[] | select(.role == "'"$role"'")] | flatten' <<< "$auths")
    num_auth_infos=$(jq -r 'length' <<< "$auth_infos")
    if test "$num_auth_infos" -gt 1
    then
      error "Google auth has $num_auth_infos sections that configure the '$role' role, but only one can exist"
      return 1
    fi
    _exec_rosa create idp \
      -c "$(_rosa_cluster_name)-$type" \
      --type google \
      --name "google-$role" \
      --client-id "$client_id" \
      --client-secret "$client_secret" \
      --hosted-domain "$hosted_domain" \
      --yes
    while read -r email
    do
      info "Granting '$email' '$role' access"
      _exec_rosa grant user "$role" --user="$email" -c "$(_rosa_cluster_name)-$type"
    done < <(jq -r '.[0].users[].name' <<< "$auth_infos" | grep -iv null | cat)
  done
}

set_up_basic_idp() {
  _idp_exists() {
    _exec_rosa list idps -c "$(_rosa_cluster_name)-$1" |
      grep -q "$2"
  }
  local type
  type="$1"

  _rosa_cluster_type_disabled "$type" && return 0
  auths=$(_get_from_config '.deploy.cluster_config.cluster_auth.basic.auths')
  for role in $(yq -r '.[].role' <<< "$auths" | sort -u)
  do
    { test -z "$role" || test "${role,,}" == null ; } && continue
    _idp_exists "$type" "basic-${role}" && return 0
    auths=$(_get_from_config '.deploy.cluster_config.cluster_auth.basic.auths')
    { test -z "$auths" || test "$auths" == '[]'; } && return 0
    auth_infos=$(yq -o=j -I=0 -r '[.[] | select(.role == "'"$role"'")] | flatten' <<< "$auths")
    num_auth_infos=$(jq -r 'length' <<< "$auth_infos")
    if test "$num_auth_infos" -gt 1
    then
      error "Basic auth has $num_auth_infos sections that configure the '$role' role, but only one can exist"
      return 1
    fi
    users=$(jq -r '[.[0].users[] | .name + ":" + .password] | join(",")' <<< "$auth_infos")
    _exec_rosa create idp \
      -c "$(_rosa_cluster_name)-$type" \
      --type htpasswd \
      --name "basic-$role" \
      --users "$users" \
      --yes
    while read -r email
    do
      info "Granting '$email' '$role' access"
      _exec_rosa grant user "$role" --user="$email" -c "$(_rosa_cluster_name)-$type"
    done < <(jq -r '.[0].users[].name' <<< "$auth_infos" | grep -iv null | cat)
  done
}
deploy_network_classic
deploy_network_hcp
create_account_roles
create_oidc_configuration
create_operator_roles_classic
create_operator_roles_hcp
create_cluster_classic
set_up_google_idp classic
set_up_basic_idp classic
create_cluster_hcp
set_up_google_idp hcp
set_up_basic_idp hcp

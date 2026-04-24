#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/gcp.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/ocp.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
source "$ENVIRONMENT_INCLUDE_DIR/ocp.sh"

_update_cluster_identity_providers() {
  local idp
  idp="$1"
  echo "$idp" > /tmp/idp_info
  existing_oauth=$(exec_oc_postinstall get oauth cluster -o yaml 2>/dev/null)
  if test -z "$existing_oauth"
  then
    info "Configuring identity provider for cluster with details: $(yq -o=j -I=0 . <<< "$idp")"
    exec_oc_postinstall apply -f /tmp/idp_info
    restart_auth=true
  else
    num_existing_idps=$(exec_oc_postinstall get oauth cluster -o yaml | yq -r '.spec.identityProviders | length')
    info "Updating cluster identity provider with details: $(yq -o=j -I=0 . <<< "$idp")"
    idp=$(yq -o=j -I=0 '.spec.identityProviders[0]' /tmp/idp_info)
    idx=0
    path="/spec"
    value=$(printf '{"identityProviders":[%s]}' "$idp")
    if test "$num_existing_idps" -ge 1
    then
      idx="$((num_existing_idps-1))"
      path="/spec/identityProviders/$idx"
      value="$idp"
    fi
    exec_oc_postinstall patch oauth cluster \
      --type=json \
      -p '[{"op":"add","path":"'"$path"'","value":'"$value"'}]'
    info "Restarting OpenShift Authentication..."
    exec_oc_postinstall rollout restart -n openshift-authentication deployment/oauth-openshift
  fi
  rm /tmp/idp_info
}

_get_auth_secret_name() {
  local type role query
  type="$1"
  role="$2"
  echo "authinfo-${type,,}-$(tr -dc '[:alnum:]' <<< "${role,,}")"
}

_get_auth_secret() {
  local type role query
  type="$1"
  role="$2"
  query="$3"
  f="/tmp/auth_file_$(echo "${type}-${role}" |base64 -w 0 | tr -d '=')"
  test -f "$f" || 2>/dev/null exec_oc_postinstall get secret -n openshift-config \
    "$(_get_auth_secret_name "$type" "$role")" \
    -o yaml > "$f"
  test -s "$f" || return 0
  yq -r "$query" "$f"
}

_ensure_valid_cluster_role() {
  exec_oc_postinstall get clusterrole -o name | sed -E 's;clusterrole.rbac.authorization.k8s.io/;;' | grep -q "$1"
}

control_plane_nodes_exist() {
  local num_worker_nodes_want num_worker_nodes_want
  num_worker_nodes_want="$(_get_from_config '.deploy.node_config.control_plane.quantity_per_zone')"
  num_worker_nodes_got=$(_exec_aws ec2 describe-instances \
    --query 'Reservations[].Instances[?(State.Name == `running`) &&
(@.Tags[?Key==`aws:cloudformation:logical-id` && contains(Value, `Master`)]) &&
(@.Tags[?Key==`Name` && contains(Value, `'"$(_cluster_infra_name)"'`)])].InstanceId' --output text | wc -l)
  test "$num_worker_nodes_got" == "$num_worker_nodes_want"
}

worker_nodes_exist() {
  local num_worker_nodes_want num_worker_nodes_want
  num_worker_nodes_want="$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')"
  { test -z "$num_worker_nodes_want" || test "$num_worker_nodes_want" -eq 0; } && return 0

  num_worker_nodes_got=$(_exec_aws ec2 describe-instances \
    --query 'Reservations[].Instances[?(State.Name == `running`) &&
(@.Tags[?Key==`aws:cloudformation:logical-id` && contains(Value, `Worker`)]) &&
(@.Tags[?Key==`Name` && contains(Value, `'"$(_cluster_infra_name)"'`)])].InstanceId' --output text | wc -l)
  test "$num_worker_nodes_got" == "$num_worker_nodes_want"
}

create_installconfig_data() {
  _ignition_files_present() {
    for t in master worker bootstrap
    do
      test -f "$(_get_file_from_openshift_install_dir "$t.ign")" || return 1
    done
  }
  { control_plane_nodes_exist && worker_nodes_exist; } && return 1
  _ignition_files_present || return 0
  { install_config_data_stale && { ! control_plane_nodes_exist && ! worker_nodes_exist ; } ; } && return 0
  warning "Install config data is stale but cluster is in an inconsistent state; keeping current data for safety"
  return 1
}

create_ssh_key() {
  f="$(_get_file_from_data_dir 'id_rsa')"
  test -f "$f" && test "$(stat -c %a "$f")" -eq 600 && return 0

  info "Creating an SSH key for the nodes"
  _get_from_config 'deploy.secrets.ssh_key.data' > "$f"
  chmod 600 "$f"
}

load_keys_into_ssh_agent() {
  info "Starting SSH agent and loading keys"
  eval "$(ssh-agent -s)" &>/dev/null
  >&2 ssh-add -q "$(_get_file_from_data_dir 'id_rsa')"
}

upload_key_into_ec2() {
  info "Creating AWS EC2 key pair from SSH private key"
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  test -n "$(_exec_aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  pubkey="$(ssh-keygen -yf "$(_get_file_from_data_dir 'id_rsa')")"
  >/dev/null _exec_aws ec2 import-key-pair --key-name "$key_name" \
    --public-key-material "$(base64 -w 0 <<< "$pubkey")"
}

create_installation_manifests() {
  if ! create_installconfig_data
  then
    info "Skipping creating installation manifests"
    return 0
  fi
  info "Creating installation manifests"
  _exec_openshift_install_aws create manifests
}

remove_default_machinesets_from_installation_manifests() {
  if ! create_installconfig_data
  then
    info "Skipping openshift install manifest modification"
    return 0
  fi
  for f in '99_openshift-cluster-api_master-machines' \
    '99_openshift-machine-api_master-control-plane-machine-set' \
    '99_openshift-cluster-api_worker-machineset'
  do
    info "Deleting manifests from install dir: $f"
    find "$(_openshift_install_dir)/openshift" -type f -name "*$f*" \
      -exec rm -rf {} \;
  done
}

configure_control_plane_scheduling() {
  test -d "$(_get_file_from_openshift_install_dir 'manifests')" || return 0

  num_cp_nodes="$(_get_from_config '.deploy.node_config.control_plane.quantity_per_zone')"
  cp_schedulable="$(_get_from_config '.deploy.node_config.control_plane.schedulable' | grep -Ev '^null$' | cat)"
  test -z "$cp_schedulable" &&
    test "$num_cp_nodes" -ne 1 &&
    return 0
  info "Making control plane schedulable"
  yq -ir '.spec.mastersSchedulable = true' "$(_get_file_from_openshift_install_dir 'manifests/cluster-scheduler-02-config.yml')"
}

create_ignition_files() {
  if ! create_installconfig_data
  then
    info "Skipping creating Red Hat CoreOS ignition files"
    return 0
  fi
  info "Creating Red Hat CoreOS Ignition files"
  _exec_openshift_install_aws create ignition-configs || return 1
  for file in bootstrap master worker
  do
    test -f "${dir}/${file}.ign" && continue
    error "Couldn't find ignition file: ${dir}/${file}.ign"
    return 1
  done
}

create_vpc() {
  local subnet_size subnet_bits params params_json
	subnet_size=$(_get_from_config '.deploy.cloud_config.aws.networking.subnet_size')
	test -z "$subnet_size" && subnet_size=24
	subnet_bits=$((32-subnet_size))
  params=(
    'VpcCidr' "$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')"
    'AvailabilityZoneCount' "$(_all_availability_zones | wc -l)"
    'SubnetBits' "$subnet_bits"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
  _create_aws_resources_from_cfn_stack 'vpc' "$params_json" "Creating VPC..."
}

create_networking_resources() {
  public_subnets=$(_get_param_from_aws_cfn_stack vpc 'PublicSubnetIds')
  if test -z "$public_subnets"
  then
    error "Public subnets not available."
    return 1
  fi
  private_subnets=$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')
  if test -z "$private_subnets"
  then
    error "Private subnets not available."
    return 1
  fi
  vpc_id=$(_get_param_from_aws_cfn_stack vpc 'VpcId')
  if test -z "$vpc_id"
  then
    error "VPC ID not available."
    return 1
  fi
  params=(
    'ClusterName' "$(_cluster_name)"
    'InfrastructureName' "$(_cluster_infra_name)"
    'HostedZoneId' "$(_hosted_zone_id)"
    'HostedZoneName' "$(_hosted_zone_name)"
    'PublicSubnets' "$public_subnets"
    'PrivateSubnets' "$private_subnets"
    'VpcId' "$vpc_id"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}")
  _create_aws_resources_from_cfn_stack_with_caps networking "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating DNS records, load balancers and target groups..."
}

create_security_group_rules() {
  private_subnets=$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')
  if test -z "$private_subnets"
  then
    error "Private subnets not available."
    return 1
  fi
  vpc_id=$(_get_param_from_aws_cfn_stack vpc 'VpcId')
  if test -z "$vpc_id"
  then
    error "VPC ID not available."
    return 1
  fi
  params=(
    'InfrastructureName' "$(_cluster_infra_name)"
    'VpcId' "$vpc_id"
    'VpcCidr' "$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')"
    'PrivateSubnets' "$private_subnets"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}")
  _create_aws_resources_from_cfn_stack_with_caps security "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating security groups..."
}

create_bootstrap_machine() {
  test -f "$(_get_file_from_openshift_install_dir '.bootstrap_complete')" && return 0

  set -e
  sg_id=$(fail_if_nil "$(_get_param_from_aws_cfn_stack security 'MasterSecurityGroupId')" \
    "Master security group ID not found")
  private_subnets=$(fail_if_nil "$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')" \
    "Private subnets not found")
  vpc_id=$(fail_if_nil "$(_get_param_from_aws_cfn_stack vpc 'VpcId')" "VPC ID not found")
  lambda_arn=$(fail_if_nil "$(_get_param_from_aws_cfn_stack networking 'RegisterNlbIpTargetsLambda')" \
    "NLB registration Lambda ARN not found")
  ext_api_target_group_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'ExternalApiTargetGroupArn')" \
    'External API NLB target group ARN not found')
  int_api_target_group_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'InternalApiTargetGroupArn')" \
    'Internal API NLB target group ARN not found')
  int_svc_target_group_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'InternalServiceTargetGroupArn')" \
    'Internal service NLB target group ARN not found')
  params=(
    'InfrastructureName' "$(_cluster_infra_name)"
    'RhcosAmi' "$(fail_if_nil "$(_rhcos_ami_id)" "CoreOS AMI ID not found")"
    'AllowedBootstrapSshCidr' "$(fail_if_nil "$(_this_ip)/32" "Couldn't resolve IP address")"
    'PublicSubnet' "$(_bootstrap_subnet)"
    'MasterSecurityGroupId' "$sg_id"
    'BootstrapInstanceType' "$(_get_from_config '.deploy.node_config.bootstrap.instance_type')"
    'BootstrapIgnitionLocation' "s3://$(_cluster_ignition_files_bucket)/bootstrap.ign"
    'AutoRegisterELB' 'yes'
    'RegisterNlbIpTargetsLambdaArn' "$lambda_arn"
    'ExternalApiTargetGroupArn' "$ext_api_target_group_arn"
    'InternalApiTargetGroupArn' "$int_api_target_group_arn"
    'InternalServiceTargetGroupArn' "$int_svc_target_group_arn"
    'VpcId' "$vpc_id"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}")
  _create_aws_resources_from_cfn_stack_with_caps bootstrap_machine "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating bootstrap node..." &&
      touch -f "$(_get_file_from_openshift_install_dir '.bootstrap_complete')"
}

create_ignition_bucket_in_s3() {
  test -n "$(2>/dev/null _exec_aws s3api head-bucket \
    --bucket "$(_cluster_ignition_files_bucket)")" &&
    return 0
  info "Creating S3 bucket for ignition files..."
  _exec_aws s3 mb "s3://$(_cluster_ignition_files_bucket)"
}

sync_bootstrap_ignition_files_with_s3_bucket() {
  info "Syncing ignition files with ignition S3 bucket"
  _exec_aws s3 sync \
    --exclude '*' \
    --include '*.ign' \
    "$(_openshift_install_dir)" \
    "s3://$(_cluster_ignition_files_bucket)"
}

create_openshift_install_config_file() {
  _subnet_ids_as_yaml_list() {
    local ids
    ids=$(tr ',' '\n' <<< "$1" |
      grep -Ev '^$' |
      sort -u)
    grep -q 'Public' <<< "$1" && ids=$(grep -v "$(_bootstrap_subnet)" <<< "$ids")
    echo "$ids" | as_yaml_list
  }
  enable_sno=false
  num_cp_nodes="$(_get_from_config '.deploy.node_config.control_plane.quantity_per_zone')"
  test "$num_cp_nodes" -eq 1 && enable_sno=true
  local values file external_subnet_ids internal_subnet_ids
  external_subnet_ids=$(_subnet_ids_as_yaml_list "$(_get_param_from_aws_cfn_stack vpc 'PublicSubnetIds')")
  internal_subnet_ids=$(_subnet_ids_as_yaml_list "$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')")
  num_workers="$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')"
  if test "$num_workers" -eq 0
  then
    values=(
      ssh_key "$(fail_if_nil "$(ssh-keygen -yf "$(_get_file_from_data_dir 'id_rsa')")" \
        "Couldn't obtain public key from SSH private key.")"
      base_domain "$(_hosted_zone_name)"
      aws_hosted_zone_id "$(_hosted_zone_id)"
      rhcos_ami_id "$(_rhcos_ami_id)"
      cluster_name "$(_cluster_name)"
      aws_region "$(_get_from_config '.deploy.cloud_config.aws.networking.region')"
      pull_secret "$(_get_from_config '.deploy.node_config.common.pull_secret' | as_json_string)"
      control_plane_node_azs "$(_get_from_config '.deploy.cloud_config.aws.networking.availability_zones.control_plane[]' | as_yaml_list)"
      control_plane_node_instance_type "$(_get_from_config '.deploy.node_config.control_plane.instance_type')"
      control_plane_security_groups "$(_get_param_from_aws_cfn_stack security 'MasterSecurityGroupId' | as_yaml_list)"
      bootstrap_node_subnet_id "$(_bootstrap_subnet)"
      control_plane_instance_profile "$(_get_param_from_aws_cfn_stack security 'MasterInstanceProfile')"
      worker_security_groups "$(_get_param_from_aws_cfn_stack security 'MasterSecurityGroupId' | as_yaml_list)"
      worker_instance_profile "$(_get_param_from_aws_cfn_stack security 'WorkerInstanceProfile')"
      external_subnet_ids "$external_subnet_ids"
      internal_subnet_ids "$internal_subnet_ids"
      disable_workers "true"
      worker_node_azs '[]'
      worker_node_instance_type 'not-used'
      enable_sno "$enable_sno"
    )
  else
    values=(
      ssh_key "$(fail_if_nil "$(ssh-keygen -yf "$(_get_file_from_data_dir 'id_rsa')")" \
        "Couldn't obtain public key from SSH private key.")"
      base_domain "$(_hosted_zone_name)"
      aws_hosted_zone_id "$(_hosted_zone_id)"
      rhcos_ami_id "$(_rhcos_ami_id)"
      cluster_name "$(_cluster_name)"
      aws_region "$(_get_from_config '.deploy.cloud_config.aws.networking.region')"
      pull_secret "$(_get_from_config '.deploy.node_config.common.pull_secret' | as_json_string)"
      control_plane_node_azs "$(_get_from_config '.deploy.cloud_config.aws.networking.availability_zones.control_plane[]' | as_yaml_list)"
      control_plane_node_instance_type "$(_get_from_config '.deploy.node_config.control_plane.instance_type')"
      control_plane_security_groups "$(_get_param_from_aws_cfn_stack security 'MasterSecurityGroupId' | as_yaml_list)"
      worker_node_azs "$(_get_from_config '.deploy.cloud_config.aws.networking.availability_zones.workers[]'|
        as_yaml_list)"
      worker_node_instance_type "$(_get_from_config '.deploy.node_config.workers.instance_type')"
      worker_security_groups "$(_get_param_from_aws_cfn_stack security 'MasterSecurityGroupId' | as_yaml_list)"
      bootstrap_node_subnet_id "$(_bootstrap_subnet)"
      control_plane_instance_profile "$(_get_param_from_aws_cfn_stack security 'MasterInstanceProfile')"
      worker_instance_profile "$(_get_param_from_aws_cfn_stack security 'WorkerInstanceProfile')"
      external_subnet_ids "$external_subnet_ids"
      internal_subnet_ids "$internal_subnet_ids"
      disable_workers "false"
      enable_sno "$enable_sno"
    )
  fi
  render_and_save_install_config "${values[@]}"
}

# The number of IAM permissions we need to grant this user will trigger a PolicySize
# validation error. The YAML template splits them up into policies with 80 actions each.
create_cluster_iam_user_policies() {
  local policy_doc infra_name policy_arn
  infra_name="$(_cluster_infra_name)"
  policy_name="${infra_name}-cluster_user-policy"
  policy_arn=$(_exec_aws iam list-policies |
    jq --arg name "$policy_name" '.Policies[] | select(.PolicyName == $name) | .Arn')
  test -n "$policy_arn" && return 0

  policy_doc=$(render_yaml_template_with_values_file \
    iam-cluster-user \
    "$ENVIRONMENT_INCLUDE_DIR/iam_permissions.yaml"
  )
  if test -z "$policy_doc"
  then
    error "Failed to render policy doc for cluster user"
    return 1
  fi
  for idx in $(seq 1 "$(yq length <<< "$policy_doc")")
  do
    n="${policy_name}-Part${idx}"
    test -n "$(_exec_aws iam list-policies --query 'Policies[?PolicyName==`'"$n"'`]' --output text)" &&
      continue
    info "Creating cluster user IAM policy #$idx"
    _exec_aws iam create-policy --policy-name "$n" \
      --policy-doc "$(yq -o=j -I=0 ".[$((idx-1))]" <<< "$policy_doc")"
  done
}

create_cluster_iam_user() {
  infra_name="$(_cluster_infra_name)"
  policy_name="${infra_name}-cluster_user-policy"
  policy_arns=$(_exec_aws iam list-policies |
    jq -r --arg name "$policy_name" '.Policies[] | select(.PolicyName|contains($name)) | .Arn'  |
    grep -v null |
    cat)
  if test -z "$policy_arns"
  then
    error "Cluster user policy ARN not created."
    return 0
  fi
  params=(
    InfrastructureName "$(_cluster_infra_name)"
    UserNameBase "$(_cluster_infra_name)"
    PolicyArns "$(as_csv <<< "$policy_arns")"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}")
  _create_aws_resources_from_cfn_stack_with_caps cluster_user "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating cluster user..."
}

create_control_plane_machines() {
  set -e
  sg_id=$(fail_if_nil "$(_get_param_from_aws_cfn_stack security 'MasterSecurityGroupId')" \
    "Master security group ID not found")
  private_subnets=$(fail_if_nil "$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')" \
    "Private subnets not found")
  lambda_arn=$(fail_if_nil "$(_get_param_from_aws_cfn_stack networking 'RegisterNlbIpTargetsLambda')" \
    "NLB registration Lambda ARN not found")
  ext_api_target_group_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'ExternalApiTargetGroupArn')" \
    'External API NLB target group ARN not found')
  int_api_target_group_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'InternalApiTargetGroupArn')" \
    'Internal API NLB target group ARN not found')
  int_svc_target_group_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'InternalServiceTargetGroupArn')" \
    'Internal service NLB target group ARN not found')
  cert_authority=$(get_data_from_ignition_file master '.ignition.security.tls.certificateAuthorities[0].source')
  if test -z "$cert_authority"
  then
    error "Couldn't get cert authority from ignition file"
    return 1
  fi
  instance_profile_name=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack security MasterInstanceProfile)" \
    "Couldn't obtain instance profile for primary node.")
  api_server_fqdn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'ApiServerDnsName')" \
    "Couldn't get API server DNS name.")
  params=(
    'InfrastructureName' "$(_cluster_infra_name)"
    'RhcosAmi' "$(fail_if_nil "$(_rhcos_ami_id)" "CoreOS AMI ID not found")"
    'MasterSecurityGroupId' "$sg_id"
    'MasterInstanceType' "$(_get_from_config '.deploy.node_config.control_plane.instance_type')"
    'RegisterNlbIpTargetsLambdaArn' "$lambda_arn"
    'ExternalApiTargetGroupArn' "$ext_api_target_group_arn"
    'InternalApiTargetGroupArn' "$int_api_target_group_arn"
    'InternalServiceTargetGroupArn' "$int_svc_target_group_arn"
    'Master0Subnet' "$(cut -f1 -d ',' <<< "$private_subnets")"
    'Master1Subnet' "$(cut -f2 -d ',' <<< "$private_subnets")"
    'Master2Subnet' "$(cut -f3 -d ',' <<< "$private_subnets")"
    'IgnitionLocation' "https://${api_server_fqdn}:22623/config/master"
    'CertificateAuthorities' "$cert_authority"
    'MasterInstanceProfileName' "$instance_profile_name"
    'NumNodes' "$(_get_from_config '.deploy.node_config.control_plane.quantity_per_zone')"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}")
  _create_aws_resources_from_cfn_stack_with_caps control_plane_machines "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating the control plane nodes..."
}

create_worker_machines() {
  set -e
  num_workers="$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')"
  if test -z "$num_workers" || test "$num_workers" -eq 0
  then
    info "No workers in this environment; control plane will be schedulable"
    return 0
  fi

  sg_id=$(fail_if_nil "$(_get_param_from_aws_cfn_stack security 'WorkerSecurityGroupId')" \
    "Master security group ID not found")
  private_subnets=$(fail_if_nil "$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')" \
    "Private subnets not found")
  cert_authority=$(get_data_from_ignition_file worker '.ignition.security.tls.certificateAuthorities[0].source')
  if test -z "$cert_authority"
  then
    error "Couldn't get cert authority from ignition file"
    return 1
  fi
  instance_profile_name=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack security WorkerInstanceProfile)" \
    "Couldn't obtain instance profile for primary node.")
  for idx in $(seq 0 "$num_workers")
  do
    params=(
      'InfrastructureName' "$(_cluster_infra_name)"
      'RhcosAmi' "$(fail_if_nil "$(_rhcos_ami_id)" "CoreOS AMI ID not found")"
      'Subnet0' "$(cut -f1 -d ',' <<< "$private_subnets")"
      'Subnet1' "$(cut -f2 -d ',' <<< "$private_subnets")"
      'Subnet2' "$(cut -f3 -d ',' <<< "$private_subnets")"
      'WorkerSecurityGroupId' "$sg_id"
      'WorkerInstanceType' "$(_get_from_config '.deploy.node_config.workers.instance_type')"
      'CertificateAuthorities' "$cert_authority"
      'WorkerInstanceProfileName' "$instance_profile_name"
      'IgnitionLocation' "https://${api_server_fqdn}:22623/config/worker"
      'NumWorkers' "$num_workers"
    )
    params_json=$(_create_aws_cf_params_json "${params[@]}")
    _create_aws_resources_from_cfn_stack_with_caps \
      worker_nodes "$params_json" \
      "CAPABILITY_NAMED_IAM" \
      "Creating $num_workers workers..."
  done
}

wait_for_bootstrap_complete() {
  test -f "$(_get_file_from_openshift_install_dir '.bootstrap_complete')" && return 0
  _exec_openshift_install_aws wait-for bootstrap-complete --log-level debug
}

wait_for_install_to_complete() {
  _exec_openshift_install_aws wait-for install-complete --log-level debug
}

wait_for_first_worker_csr() {
  done_file="$(_get_file_from_openshift_install_dir '.first_worker_joined')"
  test -f "$done_file" && return 0

  num_workers="$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')"
  test "$num_workers" -eq 0 && return 0

  attempts=0
  max_attempts=180
  while test "$attempts" -lt "$max_attempts"
  do
    info "[Attempt $attempts/$max_attempts] Waiting for the first worker node bootstrapper CSR to appear"
    set +e
    results=$(exec_oc_postinstall get csr 2>&1 |
      grep -v "No resources found" |
      grep -E "node-bootstrapper.*Pending" |
      cut -f1 -d ' ')
    num_results=$(grep -Evc '^$' <<< "$results")
    set -e
    if test "$num_results" -gt 0
    then
      touch "$done_file"
      return 0
    fi
    attempts=$((attempts+1))
    sleep 1
  done
  return 1
}

wait_for_and_register_worker_node_csrs() {
  _get_csrs() {
    local query state
    query=$1
    state=$2
    exec_oc_postinstall get csr 2>&1 |
      grep -v "No resources found" |
      grep -E "${query}.*$state" |
      cut -f1 -d ' '
  }
  _num_csrs() {
    grep -Evc '^$' <<< "$1"
  }
  _approve_csrs() {
    grep -Ev '^$' <<< "$1" |
      while read -r csr
      do
        info "--> Approving pending '$2' CSR [$csr]"
        exec_oc_postinstall adm certificate approve "$csr"
      done
  }
  test -f "$(_get_file_from_openshift_install_dir '.csrs_accepted')" && return 0
  num_workers="$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')"
  test "$num_workers" -eq 0 && return 0

  local attempts max_attempts successes successes_required
  successes_required=10
  max_attempts=180
  attempts=0
  successes=0
  while test "$attempts" -lt "$max_attempts"
  do
    if test "$successes" == "$successes_required"
    then
      touch "$(_get_file_from_openshift_install_dir '.csrs_accepted')"
      return 0
    fi

    approved_bootstrapper_csrs=$(_get_csrs 'node-bootstrapper' 'Approved')
    approved_serving_csrs=$(_get_csrs 'kubelet-serving' 'Approved')
    pending_bootstrapper_csrs=$(_get_csrs 'node-bootstrapper' 'Pending')
    pending_serving_csrs=$(_get_csrs 'kubelet-serving' 'Pending')
    info "[Attempt $attempts/$max_attempts] Registering worker node CSRs:
      approved (bootstrapper): $(_num_csrs "$approved_bootstrapper_csrs")
      approved (kubelet serving): $(_num_csrs "$approved_serving_csrs")
      pending (bootstrapper): $(_num_csrs "$pending_bootstrapper_csrs")
      pending (kubelet serving): $(_num_csrs "$pending_serving_csrs")
      zero-CSR confirmations remaining: $((successes_required-successes))"
    if test "$(_num_csrs "$pending_bootstrapper_csrs")" == 0 &&
       test "$(_num_csrs "$pending_serving_csrs")" == 0
    then
      successes=$((successes+1))
      sleep 0.5
      continue
    else
      successes=0
    fi
    _approve_csrs "$pending_bootstrapper_csrs" 'bootstrapper'
    _approve_csrs "$pending_serving_csrs" 'kubelet serving'
    attempts=$((attempts+1))
  done
}

wait_for_workers_to_become_ready() {
  num_workers="$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')"
  test "$num_workers" -eq 0 && return 0
  local num_worker_nodes max_attempts
  num_worker_nodes=$(_exec_aws ec2 describe-instances \
    --query 'Reservations[].Instances[?(State.Name == `running`) && 
(@.Tags[?Key==`aws:cloudformation:logical-id` && contains(Value, `Worker`)]) &&
(@.Tags[?Key==`Name` && contains(Value, `'"$(_cluster_infra_name)"'`)])].InstanceId' --output text | wc -l)
  max_attempts=100
  while test "$max_attempts" -gt 0
  do
    ready_workers=$(exec_oc_postinstall get node | grep -E ' Ready.*worker ' | wc -l)
    test "$ready_workers" == "$num_worker_nodes" && return 0
    info "[$((100-max_attempts))] Waiting for nodes to become ready (want: $num_worker_nodes, got: $ready_workers)"
    max_attempts=$((max_attempts-1))
    sleep 1
  done
}

create_ingress_dns_records() {
  local router_elb_hosted_zone_id private_hosted_zone_id private_hosted_zone_name
  private_hosted_zone_id=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'PrivateHostedZoneId')" \
    "Private hosted zone ID not found.")
  private_hosted_zone_name=$(_exec_aws route53 get-hosted-zone --id "$private_hosted_zone_id" --query 'HostedZone.Name'\
    --output text | sed -E 's/\.$//')
  if test -z "$private_hosted_zone_name"
  then
    error "Hosted zone name not found from ID $private_hosted_zone_id"
    return 1
  fi
  router_elb_fqdn=$(_cluster_router_fqdn) || return 1
  router_elb_hosted_zone_id=$(_exec_aws elb describe-load-balancers |
    jq -r '.LoadBalancerDescriptions[] | select(.DNSName == "'"$router_elb_fqdn"'").CanonicalHostedZoneNameID') || return 1
  params=(
    'ClusterName' "$(_cluster_name)"
    'HostedZoneId' "$(_hosted_zone_id)"
    'HostedZoneName' "$(_hosted_zone_name)"
    'RouterELBHostedZoneId' "$router_elb_hosted_zone_id"
    'RouterELBFQDN' "$(_cluster_router_fqdn)."
    'PrivateHostedZoneId' "$private_hosted_zone_id"
    'PrivateHostedZoneName' "$private_hosted_zone_name"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}")
  _create_aws_resources_from_cfn_stack_with_caps ingress "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating DNS records for ingress into the cluster..."
}

delete_bootstrap_machine() {
  _delete_aws_resources_from_cfn_stack bootstrap_machine \
    "Install complete; deleting bootstrap machine..."
}

wait_for_ingress_load_balancer_to_be_created() {
  local attempts max_attempts router_elb_hosted_zone_id
  attempts=0
  max_attempts=180
  while test "$attempts"  -lt "$max_attempts"
  do
    router_elb_fqdn=$(_cluster_router_fqdn)
    if test -z "$router_elb_fqdn"
    then
      attempts=$((attempts+1))
      sleep 1
      continue
    fi
    router_elb_hosted_zone_id=$(_exec_aws elb describe-load-balancers |
      jq -r '.LoadBalancerDescriptions[] | select(.DNSName == "'"$router_elb_fqdn"'").CanonicalHostedZoneNameID')
    test -n "$router_elb_hosted_zone_id" && return 0
    info "[Attempt $attempts/$max_attempts] Waiting for ingress ELB to be created"
    attempts=$((attempts+1))
    sleep 1
  done
  return 1
}

create_cluster_users_htpasswd() {
  _user_exists_in_htpasswd_secret() {
    local user role data
    user="$1"
    role="$2"
    data=$(_get_auth_secret basic "$role" '.data.htpasswd')
    test -z "$data" && return 1
    echo "$data" | base64 -d | grep -Eq "^${user}:"
  }

  auths=$(_get_from_config '.deploy.cluster_config.cluster_auth.basic.auths')
  { test -z "$auths" || test "$auths" == '[]'; } && return 0

  restart_auth=false
  for role in $(yq -r '.[].role' <<< "$auths" | sort -u)
  do
    { test -z "$role" || test "${role,,}" == null ; } && continue
    if ! _ensure_valid_cluster_role "$role"
    then
      error "Not a valid cluster role: $role"
      return 1
    fi
    auth_infos=$(yq -o=j -I=0 -r '[.[] | select(.role == "'"$role"'")] | flatten' <<< "$auths")
    num_auth_infos=$(jq -r 'length' <<< "$auth_infos")
    if test "$num_auth_infos" -gt 1
    then
      error "Basic auth has $num_auth_infos sections that configure the '$role' role, but only one can exist"
      return 1
    fi
    changes_made=false
    htpasswd_file="$(mktemp /tmp/htpasswd.XXXXXXXX)"
    while read -r userdata
    do
      username=$(jq -r '.name' <<< "$userdata" | grep -iv null | cat)
      if test -z "$username"
      then
        error "One of the users in the '$role' section has a blank username."
        return 1
      fi
      test "${username,,}" == null && continue
      _user_exists_in_htpasswd_secret "$username" "$role" && continue

      password=$(jq -r '.password' <<< "$userdata" | grep -iv null | cat)
      if test -z "$password"
      then
        error "One of the users in the '$role' section has a blank password."
        return 1
      fi
      info "Creating basic auth user '$username' (role: $role)"
      htpasswd -c -B -b "$htpasswd_file" "$username" "$password" || return 1
      info "Granting '$username' $role access"
      exec_oc_postinstall adm policy add-cluster-role-to-user "$role" "$username"
      changes_made=true
    done < <(jq -cr '.[0].users[]' <<< "$auth_infos")
    if test "$changes_made" == true
    then
      info "Saving login details to cluster"
      exec_oc_postinstall delete secret -n openshift-config "$(_get_auth_secret_name basic "$role")" 2>/dev/null || true
      exec_oc_postinstall create secret generic -n openshift-config \
        --from-file=htpasswd="$htpasswd_file" \
        "$(_get_auth_secret_name basic "$role")"
      _update_cluster_identity_providers "$(cat <<-EOF
  apiVersion: config.openshift.io/v1
  kind: OAuth
  metadata:
    name: cluster
  spec:
    identityProviders:
    - name: basic-$role
      mappingMethod: claim 
      type: HTPasswd
      htpasswd:
        fileData:
          name: $(_get_auth_secret_name basic "$role")
EOF
)"
      exec_oc_postinstall rollout restart -n openshift-authentication deployment/oauth-openshift
    fi
  done
}

create_cluster_users_google_auth() {
  _client_secret_exists_in_secret() {
    local client_secret role data
    client_secret="$1"
    role="$2"
    test "$client_secret" == "$(_get_auth_secret google "$role" '.data.clientSecret' | base64 -d)"
  }

  _google_idp_exists() {
    local role
    role="$1"
    test -n "$(exec_oc_postinstall get oauth cluster -o yaml |
      yq -r ".spec.identityProviders[] | select(.name == \"google-$role\") | .name"  |
      grep -Ev '^null$' |
      cat)"
  }

  auths=$(_get_from_config '.deploy.cluster_config.cluster_auth.google_oauth.auths')
  { test -z "$auths" || test "$auths" == '[]'; } && return 0

  details=$(_get_from_config '.deploy.cluster_config.cluster_auth.google_oauth.additional_details')
  for role in $(yq -r '.[].role' <<< "$auths" | sort -u)
  do
    { test -z "$role" || test "${role,,}" == null ; } && continue
    if ! _ensure_valid_cluster_role "$role"
    then
      error "Not a valid cluster role: $role"
      return 1
    fi
    auth_infos=$(yq -o=j -I=0 -r '[.[] | select(.role == "'"$role"'")] | flatten' <<< "$auths")
    num_auth_infos=$(jq -r 'length' <<< "$auth_infos")
    if test "$num_auth_infos" -gt 1
    then
      error "Google auth has $num_auth_infos sections that configure the '$role' role, but only one can exist"
      return 1
    fi
    changes_made=false
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
    if ! _client_secret_exists_in_secret "$client_secret"
    then
      info "Mapping Google OAuth app '$client_id' to role '$role'"
      exec_oc_postinstall delete secret -n openshift-config "$(_get_auth_secret_name google "$role")" 2>/dev/null || true
      exec_oc_postinstall create secret generic -n openshift-config \
        --from-literal=clientSecret="$client_secret" \
        "$(_get_auth_secret_name google "$role")"
    fi
    if ! _google_idp_exists "$role"
    then
      _update_cluster_identity_providers "$(cat <<-EOF
  apiVersion: config.openshift.io/v1
  kind: OAuth
  metadata:
    name: cluster
  spec:
    identityProviders:
    - name: google-$role
      mappingMethod: claim
      type: Google
      google:
        hostedDomain: $hosted_domain
        clientID: $client_id
        clientSecret:
          name: $(_get_auth_secret_name google "$role")
EOF
)"
    fi
    while read -r email
    do
      info "Granting '$email' '$role' access"
      exec_oc_postinstall adm policy add-cluster-role-to-user "$role" "$email"
    done < <(jq -r '.[0].users[].name' <<< "$auth_infos" | grep -iv null | cat)
  done
}

enable_nested_virtualization_on_worker_nodes() {
  _exec_ec2_instance_op_and_wait() {
    local instance_id want_state change_state change_op
    instance_id="$1"
    want_state="$2"
    change_state="$3"
    change_op="$4"
    attempts=0
    max_attempts=180
    want_state="$2"
    while test "$attempts" -ne "$max_attempts"
    do
      state=$(aws ec2 describe-instances --instance-id "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' --output text)
      case "${state,,}" in
        "${change_state,,}")
          info "---> [$instance_id] Changing '$state'"
           _exec_aws ec2 "${change_op}" --instance-id "$instance_id" || return 1
           ;;
        "${want_state,,}")
          return 0
          ;;
        *)
          info "---> [$instance_id] Waiting for state '$want_state'; got '$state'"
          attempts=$((attempts+1))
          sleep 1
          ;;
      esac
    done
    return 1
  }

  _shut_down_and_wait() {
    _exec_ec2_instance_op_and_wait "$1" 'stopped' 'running' 'stop-instances'
  }

  _start_instance_and_wait() {
    _exec_ec2_instance_op_and_wait "$1" 'running' 'stopped' 'start-instances'
  }

  test -f "$(_get_file_from_openshift_install_dir '.nested_virt_configured')" && return 0
  instances=$(_exec_aws ec2 describe-instances \
    --query 'Reservations[].Instances[?(@.Tags[?Key==`aws:cloudformation:logical-id` && contains(Value, `Worker`)]) &&
(@.Tags[?Key==`Name` && contains(Value, `'"$(_cluster_infra_name)"'`)])]' |
    jq -cr 'flatten | .[] |
select(.InstanceType | test("^(c8i|m8i|r8i)")) |
{
  id: .InstanceId,
  size: .InstanceType,
  cpuOptions: .CpuOptions
}')
  if test -z "$instances"
  then
    touch "$(_get_file_from_openshift_install_dir '.nested_virt_configured')"
    return 0
  fi
  for instance_data in $instances
  do
    instance_virt_enabled=$(jq -r '.cpuOptions.virtEnabled' <<< "$instance_data")
    test "$instance_virt_enabled" == enabled &&
      _start_instance_and_wait "$instance_id" &&
      continue

    instance_id=$(jq -r '.id' <<< "$instance_data")
    cores=$(jq -r '.cpuOptions.CoreCount' <<< "$instance_data")
    threads_per_core=$(jq -r '.cpuOptions.ThreadsPerCore' <<< "$instance_data")
    info "Enabling virtualization for worker instance '$instance_id'"
    _shut_down_and_wait "$instance_id"
    _exec_aws ec2 modify-instance-cpu-options --instance-id "$instance_id" \
      --core-count "$cores" \
      --threads-per-core "$threads_per_core" \
      --nested-virtualization enabled
    _start_instance_and_wait "$instance_id"
  done
  touch "$(_get_file_from_openshift_install_dir '.nested_virt_configured')"
}

map_cluster_admin_to_cluster_admins() {
  exec_oc_postinstall adm policy add-cluster-role-to-group cluster-admin 'system:cluster-admins'
}

create_ssh_key
load_keys_into_ssh_agent
upload_key_into_ec2
create_ignition_bucket_in_s3
create_cluster_iam_user_policies
create_cluster_iam_user
create_vpc
create_networking_resources
create_security_group_rules
create_openshift_install_config_file
create_installation_manifests
remove_default_machinesets_from_installation_manifests
configure_control_plane_scheduling
create_ignition_files
sync_bootstrap_ignition_files_with_s3_bucket
create_bootstrap_machine
create_control_plane_machines
create_worker_machines
enable_nested_virtualization_on_worker_nodes
wait_for_bootstrap_complete
wait_for_first_worker_csr
wait_for_and_register_worker_node_csrs
wait_for_workers_to_become_ready
wait_for_ingress_load_balancer_to_be_created
create_ingress_dns_records
wait_for_install_to_complete
delete_bootstrap_machine
create_cluster_users_htpasswd
create_cluster_users_google_auth
map_cluster_admin_to_cluster_admins

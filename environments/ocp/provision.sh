#!/usr/bin/env bash
set -e
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/aws.sh"
source "$ENVIRONMENT_INCLUDE_DIR/ocp.sh"

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
  test -n "$(aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  pubkey="$(ssh-keygen -yf "$(_get_file_from_data_dir 'id_rsa')")"
  >/dev/null aws ec2 import-key-pair --key-name "$key_name" \
    --public-key-material "$(base64 -w 0 <<< "$pubkey")"
}

create_ignition_files() {
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
    'ClusterName' "$(_get_from_config '.deploy.cluster_config.names.cluster')"
    'InfrastructureName' "$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
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
    'InfrastructureName' "$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
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
    'InfrastructureName' "$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
    'RhcosAmi' "$(fail_if_nil "$(_rhcos_ami_id)" "CoreOS AMI ID not found")"
    'AllowedBootstrapSshCidr' "$(fail_if_nil "$(_this_ip)/32" "Couldn't resolve IP address")"
    'PublicSubnet' "$(_bootstrap_subnet)"
    'MasterSecurityGroupId' "$sg_id"
    'BootstrapInstanceType' "$(_get_from_config '.deploy.node_config.bootstrap.instance_type')"
    'BootstrapIgnitionLocation' "s3://$(_get_from_config '.deploy.node_config.common.ignition_file_s3_bucket')/bootstrap.ign"
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
    "Creating bootstrap node..."
}

create_ignition_bucket_in_s3() {
  test -n "$(2>/dev/null aws s3api head-bucket \
    --bucket "$(_get_from_config '.deploy.node_config.common.ignition_file_s3_bucket')")" &&
    return 0
  info "Creating S3 bucket for ignition files..."
  aws s3 mb "s3://$(_get_from_config '.deploy.node_config.common.ignition_file_s3_bucket')"
}

sync_bootstrap_ignition_files_with_s3_bucket() {
  info "Syncing ignition files with ignition S3 bucket"
  aws s3 sync \
    --exclude '*' \
    --include '*.ign' \
    "$(_get_file_from_data_dir 'openshift-install')" \
    "s3://$(_get_from_config '.deploy.node_config.common.ignition_file_s3_bucket')"
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
  local values file external_subnet_ids internal_subnet_ids
  external_subnet_ids=$(_subnet_ids_as_yaml_list "$(_get_param_from_aws_cfn_stack vpc 'PublicSubnetIds')")
  internal_subnet_ids=$(_subnet_ids_as_yaml_list "$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')")
  values=(
    ssh_key "$(fail_if_nil "$(ssh-keygen -yf "$(_get_file_from_data_dir 'id_rsa')")" \
      "Couldn't obtain public key from SSH private key.")"
    base_domain "$(_hosted_zone_name)"
    aws_hosted_zone_id "$(_hosted_zone_id)"
    rhcos_ami_id "$(_rhcos_ami_id)"
    cluster_name "$(_get_from_config '.deploy.cluster_config.names.cluster')"
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
  )
  render_and_save_install_config "${values[@]}"
}

# The number of IAM permissions we need to grant this user will trigger a PolicySize
# validation error. The YAML template splits them up into policies with 80 actions each.
create_cluster_iam_user_policies() {
  local policy_doc infra_name policy_arn
  infra_name="$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
  policy_name="${infra_name}-cluster_user-policy"
  policy_arn=$(aws iam list-policies |
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
    test -n "$(aws iam list-policies --query 'Policies[?PolicyName==`'"$n"'`]' --output text)" &&
      continue
    info "Creating cluster user IAM policy #$idx"
    aws iam create-policy --policy-name "$n" \
      --policy-doc "$(yq -o=j -I=0 ".[$((idx-1))]" <<< "$policy_doc")"
  done
}

create_cluster_iam_user() {
  infra_name="$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
  policy_name="${infra_name}-cluster_user-policy"
  policy_arns=$(aws iam list-policies |
    jq -r --arg name "$policy_name" '.Policies[] | select(.PolicyName|contains($name)) | .Arn'  |
    grep -v null |
    cat)
  if test -z "$policy_arns"
  then
    error "Cluster user policy ARN not created."
    return 0
  fi
  params=(
    InfrastructureName "$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
    UserNameBase "$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
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
  private_hosted_zone_id=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack networking 'PrivateHostedZoneId')" \
    "Private hosted zone ID not found.")
  private_hosted_zone_name=$(aws route53 get-hosted-zone --id "$private_hosted_zone_id" --query 'HostedZone.Name'\
    --output text)
  if test -z "$private_hosted_zone_name"
  then
    error "Hosted zone name not found from ID $private_hosted_zone_id"
    return 1
  fi
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
    'InfrastructureName' "$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
    'RhcosAmi' "$(fail_if_nil "$(_rhcos_ami_id)" "CoreOS AMI ID not found")"
    'MasterSecurityGroupId' "$sg_id"
    'MasterInstanceType' "$(_get_from_config '.deploy.node_config.control_plane.instance_type')"
    'RegisterNlbIpTargetsLambdaArn' "$lambda_arn"
    'ExternalApiTargetGroupArn' "$ext_api_target_group_arn"
    'InternalApiTargetGroupArn' "$int_api_target_group_arn"
    'InternalServiceTargetGroupArn' "$int_svc_target_group_arn"
    'PrivateHostedZoneId' "$private_hosted_zone_id"
    'PrivateHostedZoneName' "$private_hosted_zone_name"
    'Master0Subnet' "$(cut -f1 -d ',' <<< "$private_subnets")"
    'Master1Subnet' "$(cut -f2 -d ',' <<< "$private_subnets")"
    'Master2Subnet' "$(cut -f3 -d ',' <<< "$private_subnets")"
    'IgnitionLocation' "https://${api_server_fqdn}:22623/config/master"
    'CertificateAuthorities' "$cert_authority"
    'MasterInstanceProfileName' "$instance_profile_name"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}")
  _create_aws_resources_from_cfn_stack_with_caps control_plane_machines "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating the control plane nodes..."
}

create_worker_machines() {
  set -e
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
  params=(
    'InfrastructureName' "$(_get_from_config '.deploy.cluster_config.names.infrastructure')"
    'RhcosAmi' "$(fail_if_nil "$(_rhcos_ami_id)" "CoreOS AMI ID not found")"
    'Subnet0' "$(cut -f1 -d ',' <<< "$private_subnets")"
    'Subnet1' "$(cut -f2 -d ',' <<< "$private_subnets")"
    'Subnet2' "$(cut -f3 -d ',' <<< "$private_subnets")"
    'WorkerSecurityGroupId' "$sg_id"
    'WorkerInstanceType' "$(_get_from_config '.deploy.node_config.workers.instance_type')"
    'CertificateAuthorities' "$cert_authority"
    'WorkerInstanceProfileName' "$instance_profile_name"
    'IgnitionLocation' "https://${api_server_fqdn}:22623/config/worker"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}")
  _create_aws_resources_from_cfn_stack_with_caps \
    worker_nodes "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating the workers..."
}

export $(log_into_aws) || exit 1
create_ssh_key
load_keys_into_ssh_agent
upload_key_into_ec2
create_cluster_iam_user_policies
create_cluster_iam_user
create_vpc
create_networking_resources
create_security_group_rules
create_openshift_install_config_file
create_ignition_bucket_in_s3
create_ignition_files
sync_bootstrap_ignition_files_with_s3_bucket
create_bootstrap_machine
create_control_plane_machines
create_worker_machines

#!/usr/bin/env bash
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"
source "$ENVIRONMENT_INCLUDE_DIR/eks.sh"

save_ssh_key() {
  local f
  f="$(_get_file_from_data_dir 'id_rsa')"
  test -f "$f" && test "$(stat -c %a "$f")" -eq 600 && return 0

  info "Saving SSH key to data directory"
  _get_from_config '.deploy.secrets.ssh_key.data' > "$f"
  chmod 600 "$f"
}

upload_key_into_ec2() {
  local key_name pubkey
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  test -n "$(_exec_aws ec2 describe-key-pairs --key-name "$key_name" 2>/dev/null)" && return 0

  info "Importing SSH key pair '$key_name' into EC2"
  pubkey="$(ssh-keygen -yf "$(_get_file_from_data_dir 'id_rsa')")"
  >/dev/null _exec_aws ec2 import-key-pair --key-name "$key_name" \
    --public-key-material "$(base64 -w 0 <<< "$pubkey")"
}

create_vpc() {
  local subnet_size subnet_bits params params_json
  subnet_size=$(_get_from_config '.deploy.cloud_config.aws.networking.subnet_size')
  test -z "$subnet_size" && subnet_size=24
  subnet_bits=$((32-subnet_size))
  params=(
    'InfrastructureName' "$(_eks_infra_name)"
    'VpcCidr' "$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')"
    'AvailabilityZoneCount' "$(_all_availability_zones | wc -l)"
    'SubnetBits' "$subnet_bits"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
  _create_aws_resources_from_cfn_stack 'vpc' "$params_json" "Creating VPC..."
}

create_iam_roles() {
  local params params_json
  params=(
    'InfrastructureName' "$(_eks_infra_name)"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
  _create_aws_resources_from_cfn_stack_with_caps 'iam' "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Creating IAM roles and instance profiles..."
}

create_security_groups() {
  local vpc_id params params_json
  vpc_id=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack vpc 'VpcId')" \
    "VPC ID not available") || return 1
  params=(
    'InfrastructureName' "$(_eks_infra_name)"
    'VpcCidr' "$(_get_from_config '.deploy.cloud_config.aws.networking.cidr_block')"
    'VpcId' "$vpc_id"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
  _create_aws_resources_from_cfn_stack 'security' "$params_json" \
    "Creating security groups..."
}

create_eks_cluster() {
  local cluster_role_arn cluster_sg_id public_subnets private_subnets all_subnets
  local params params_json
  cluster_role_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack iam 'EksClusterRoleArn')" \
    "EKS cluster role ARN not found") || return 1
  cluster_sg_id=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack security 'ClusterSecurityGroupId')" \
    "Cluster security group ID not found") || return 1
  public_subnets=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack vpc 'PublicSubnetIds')" \
    "Public subnet IDs not found") || return 1
  private_subnets=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')" \
    "Private subnet IDs not found") || return 1
  all_subnets="${public_subnets},${private_subnets}"
  params=(
    'InfrastructureName' "$(_eks_infra_name)"
    'EksVersion' "$(_eks_version)"
    'ClusterRoleArn' "$cluster_role_arn"
    'SubnetIds' "$all_subnets"
    'ClusterSecurityGroupId' "$cluster_sg_id"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
  _create_aws_resources_from_cfn_stack 'eks_cluster' "$params_json" \
    "Creating EKS cluster (this may take 10-15 minutes)..."
}

create_ecr() {
  repositories=$(_get_secret 'ecr-repositories')
  if test -z "$repositories"
  then
    info "No ECR repositories defined in 'ecr-repositories' secret. Skipping ECR creation."
    return 0
  fi
  yq -r '.[]' <<< "$repositories" |
    while read -r repo
    do
      local cluster_role_arn worker_node_role_arn
      cluster_role_arn=$(fail_if_nil \
        "$(_get_param_from_aws_cfn_stack iam 'EksClusterRoleArn')" \
        "EKS cluster role ARN not found") || return 1
      worker_node_role_arn=$(fail_if_nil \
        "$(_get_param_from_aws_cfn_stack iam 'WorkerNodeRoleArn')" \
        "EKS cluster worker node role ARN not found") || return 1
      instance_profile_arn=$(fail_if_nil \
        "$(_get_param_from_aws_cfn_stack iam 'WorkerInstanceProfileArn')" \
        "EKS cluster worker node instance profile role ARN not found") || return 1
      params=(
        'InfrastructureName' "$(_eks_infra_name)"
        'EksClusterRoleArn' "$cluster_role_arn"
        'EksWorkerNodeRoleArn' "$worker_node_role_arn"
        'EksWorkerNodeInstanceProfileArn' "$instance_profile_arn"
        'RepoName' "$repo"
      )
      stack_data="ecr;$(tr '/' '-' <<< "$repo")"
      params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
      _create_aws_resources_from_cfn_stack "$stack_data" \
        "$params_json" \
        "Creating ECR repository '$repo' for EKS cluster..."
    done
}

write_ecr_secrets() {
  repositories=$(_get_secret 'ecr-repositories')
  if test -z "$repositories"
  then
    info "No ECR repositories defined in 'ecr-repositories' secret. Skipping ECR creation."
    return 0
  fi
  yq -r '.[]' <<< "$repositories" |
    while read -r repo
    do
      stack_data="ecr;$(tr '/' '-' <<< "$repo")"
      repo_uri=$(fail_if_nil \
        "$(_get_param_from_aws_cfn_stack "$stack_data" 'RepositoryUri')" \
        "Repository URI not found.") || return 1
      repo_pw="$(_exec_aws ecr get-login-password)" || return 1
      _write_file_to_shared_secret_dir "$(_aws_ecr_repository "$repo" 'k8s-eks')" "$repo_uri"
      _write_file_to_shared_secret_dir "$(_aws_ecr_repository_password "$repo" 'k8s-eks')" "$repo_pw"
    done
}

generate_kubeconfig() {
  local cluster_name kubeconfig bootstrap_kubeconfig
  local cluster_endpoint cluster_ca sa_token
  cluster_name="$(_eks_infra_name)"
  kubeconfig="$(_eks_kubeconfig_path)"
  bootstrap_kubeconfig="$(_get_file_from_data_dir 'eks-bootstrap-kubeconfig')"

  info "Generating bootstrap kubeconfig for EKS cluster '$cluster_name'"
  _exec_aws eks update-kubeconfig \
    --name "$cluster_name" \
    --kubeconfig "$bootstrap_kubeconfig"

  info "Creating demoland-admin service account"
  kubectl --kubeconfig "$bootstrap_kubeconfig" apply -f - <<'SA_EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: demoland-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: demoland-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: demoland-admin
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: demoland-admin-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: demoland-admin
type: kubernetes.io/service-account-token
SA_EOF

  local token_attempts=0
  while test "$token_attempts" -lt 30
  do
    sa_token=$(kubectl --kubeconfig "$bootstrap_kubeconfig" \
      get secret demoland-admin-token -n kube-system \
      -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
    test -n "$sa_token" && break
    debug "Waiting for service account token to be populated..."
    token_attempts=$((token_attempts+1))
    sleep 1
  done
  if test -z "$sa_token"
  then
    error "Timed out waiting for demoland-admin service account token"
    return 1
  fi

  cluster_endpoint=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack eks_cluster 'ClusterEndpoint')" \
    "EKS cluster endpoint not found") || return 1
  cluster_ca=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack eks_cluster 'ClusterCertificateAuthority')" \
    "EKS cluster CA not found") || return 1

  info "Writing static kubeconfig to '$kubeconfig'"
  cat > "$kubeconfig" <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${cluster_ca}
    server: ${cluster_endpoint}
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    user: demoland-admin
  name: ${cluster_name}
current-context: ${cluster_name}
users:
- name: demoland-admin
  user:
    token: ${sa_token}
KUBECONFIG_EOF

  rm -f "$bootstrap_kubeconfig"
  info "Static kubeconfig generated (no AWS credential dependency)"
}

apply_aws_auth_configmap() {
  local worker_role_arn kubeconfig
  worker_role_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack iam 'WorkerNodeRoleArn')" \
    "Worker node role ARN not found") || return 1
  kubeconfig="$(_eks_kubeconfig_path)"
  info "Applying aws-auth ConfigMap for worker node registration"
  kubectl --kubeconfig "$kubeconfig" apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${worker_role_arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF
}

create_worker_nodes() {
  local arch ami_id worker_instance_type worker_sg_id worker_profile_arn
  local private_subnets key_name cluster_name cluster_endpoint cluster_ca cluster_cidr
  local num_worker_azs quantity_per_zone desired min max
  local params params_json

  worker_instance_type=$(_get_from_config '.deploy.node_config.workers.instance_type')
  arch="$(_aws_get_arch_from_instance_type "$worker_instance_type")"
  ami_id=$(fail_if_nil \
    "$(_eks_optimized_ami "$arch")" \
    "Could not resolve EKS-optimized AMI") || return 1
  worker_sg_id=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack security 'WorkerSecurityGroupId')" \
    "Worker security group ID not found") || return 1
  worker_profile_arn=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack iam 'WorkerInstanceProfileArn')" \
    "Worker instance profile ARN not found") || return 1
  private_subnets=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack vpc 'PrivateSubnetIds')" \
    "Private subnet IDs not found") || return 1
  key_name=$(_get_from_config '.deploy.secrets.ssh_key.name')
  cluster_name=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack eks_cluster 'ClusterName')" \
    "EKS cluster name not found") || return 1
  cluster_endpoint=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack eks_cluster 'ClusterEndpoint')" \
    "EKS cluster endpoint not found") || return 1
  cluster_ca=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack eks_cluster 'ClusterCertificateAuthority')" \
    "EKS cluster CA not found") || return 1
  cluster_cidr=$(fail_if_nil \
    "$(_exec_aws eks describe-cluster \
      --name "$cluster_name" \
      --query 'cluster.kubernetesNetworkConfig.serviceIpv4Cidr' \
      --output text)" \
    "EKS cluster service CIDR not found") || return 1

  quantity_per_zone=$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')
  num_worker_azs=$(_get_from_config '.deploy.cloud_config.aws.networking.availability_zones.workers[]' | wc -l)
  desired=$((quantity_per_zone * num_worker_azs))
  min="$num_worker_azs"
  max=$((desired + num_worker_azs))

  params=(
    'InfrastructureName' "$(_eks_infra_name)"
    'ClusterName' "$cluster_name"
    'ClusterEndpoint' "$cluster_endpoint"
    'ClusterCertificateAuthority' "$cluster_ca"
    'ClusterServiceCidr' "$cluster_cidr"
    'WorkerAmiId' "$ami_id"
    'WorkerInstanceType' "$worker_instance_type"
    'WorkerInstanceProfileArn' "$worker_profile_arn"
    'WorkerSecurityGroupId' "$worker_sg_id"
    'SubnetIds' "$private_subnets"
    'KeyName' "$key_name"
    'DesiredCapacity' "$desired"
    'MinSize' "$min"
    'MaxSize' "$max"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
  _create_aws_resources_from_cfn_stack 'worker_nodes' "$params_json" \
    "Creating $desired worker nodes..."
}

wait_for_nodes_ready() {
  local kubeconfig num_worker_azs quantity_per_zone expected attempts max_attempts ready_count
  kubeconfig="$(_eks_kubeconfig_path)"
  quantity_per_zone=$(_get_from_config '.deploy.node_config.workers.quantity_per_zone')
  num_worker_azs=$(_get_from_config '.deploy.cloud_config.aws.networking.availability_zones.workers[]' | wc -l)
  expected=$((quantity_per_zone * num_worker_azs))

  attempts=0
  max_attempts=180
  while test "$attempts" -lt "$max_attempts"
  do
    node_output=$(kubectl --kubeconfig "$kubeconfig" get nodes --no-headers 2>&1)
    if test $? -ne 0
    then
      debug "kubectl error: $node_output"
      ready_count=0
    else
      ready_count=$(grep -c ' Ready' <<< "$node_output" || true)
    fi
    if test "$ready_count" -ge "$expected"
    then
      info "All $expected worker nodes are Ready"
      return 0
    fi
    info "[Attempt $attempts/$max_attempts] Waiting for worker nodes (ready: $ready_count, expected: $expected)"
    attempts=$((attempts+1))
    sleep 10
  done
  error "Timed out waiting for $expected worker nodes to become Ready (got: $ready_count)"
  return 1
}

install_addons() {
  local cluster_name oidc_url oidc_host params params_json
  cluster_name=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack eks_cluster 'ClusterName')" \
    "EKS cluster name not found") || return 1
  oidc_url=$(fail_if_nil \
    "$(_get_param_from_aws_cfn_stack eks_cluster 'OIDCIssuerUrl')" \
    "OIDC issuer URL not found") || return 1
  oidc_host=$(sed 's;https://;;' <<< "$oidc_url")
  params=(
    'ClusterName' "$cluster_name"
    'OIDCIssuerHost' "$oidc_host"
  )
  params_json=$(_create_aws_cf_params_json "${params[@]}") || return 1
  _create_aws_resources_from_cfn_stack_with_caps 'addons' "$params_json" \
    "CAPABILITY_NAMED_IAM" \
    "Installing EKS add-ons (vpc-cni, coredns, kube-proxy, ebs-csi, s3-csi)..."
}

verify_cluster_access() {
  local kubeconfig node_output
  kubeconfig="$(_eks_kubeconfig_path)"
  info "Verifying cluster access via kubectl..."
  node_output=$(kubectl --kubeconfig "$kubeconfig" get nodes 2>&1)
  if test $? -ne 0
  then
    error "Cannot access EKS cluster:\n$node_output"
    return 1
  fi
  info "EKS cluster is accessible. Node status:"
  info "$node_output"
}

save_ssh_key
upload_key_into_ec2
create_vpc
create_iam_roles
create_security_groups
create_eks_cluster
create_ecr
write_ecr_secrets
generate_kubeconfig
apply_aws_auth_configmap
create_worker_nodes
wait_for_nodes_ready
install_addons
verify_cluster_access

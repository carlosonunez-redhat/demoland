# EKS CloudFormation Templates Plan

## Goal

Create CloudFormation templates in `./environments/k8s-eks/include/cloudformation/`
that deploy an EKS cluster into an AWS VPC. Templates only -- no infrastructure
deployment.

## Design Decisions

Based on user input:

- **Ignore `control_plane` node config** -- EKS manages the control plane; only
  worker node groups from the `workers` config will be created.
- **Self-managed nodes** -- Use Launch Templates + Auto Scaling Groups instead
  of EKS Managed Node Groups.
- **No DNS records** -- Use the default EKS-provided API endpoint URL.
- **Ignore bootstrap AZ** -- Only use `control_plane` and `workers` AZs for
  subnet placement (3 AZs from control_plane for HA subnets).

## Config Parameters Used

From `config.yaml` at `."k8s-eks".deploy`:

| Config Path | Value | Used In |
|---|---|---|
| `cluster_config.eks_version` | 1.30.1 | eks_cluster.yaml |
| `cloud_config.aws.networking.cidr_block` | 10.0.0.0/16 | vpc.yaml |
| `cloud_config.aws.networking.region` | us-east-2 | (deployment-time) |
| `cloud_config.aws.networking.availability_zones.control_plane` | 3 AZs | vpc.yaml (subnet placement) |
| `cloud_config.aws.networking.availability_zones.workers` | 2 AZs | worker_nodes.yaml |
| `cloud_config.aws.node_config.workers.quantity_per_zone` | 3 | worker_nodes.yaml |
| `cloud_config.aws.node_config.workers.instance_type` | c8i.2xlarge | worker_nodes.yaml |
| `cloud_config.aws.node_config.workers.spot` | false | worker_nodes.yaml |
| `cloud_config.aws.secrets.ssh_key` | (encrypted) | worker_nodes.yaml |

## Templates & Dependency Chain

```
vpc.yaml ──────────┐
                    ├──> security.yaml ──┐
iam.yaml ──────────┤                    ├──> eks_cluster.yaml ──┬──> worker_nodes.yaml
                    └────────────────────┘                      └──> addons.yaml
```

### 1. `vpc.yaml` -- VPC and Networking

Follows the existing `ocp-aws-upi/include/cloudformation/vpc.yaml` pattern.

**Parameters:**
- `VpcCidr` (String, default 10.0.0.0/16)
- `AvailabilityZoneCount` (Number, 1-3, default 3)
- `SubnetBits` (Number, 5-13, default 12)

**Resources:**
- VPC with DNS support/hostnames
- 1-3 public subnets (conditional on AZ count)
- 1-3 private subnets (conditional on AZ count)
- Internet Gateway + VPC attachment
- 1-3 NAT Gateways + EIPs (one per AZ)
- Public route table with IGW route
- Private route tables with NAT routes
- S3 VPC endpoint

**Outputs:** VpcId, PublicSubnetIds, PrivateSubnetIds

### 2. `iam.yaml` -- IAM Roles and Policies

**Parameters:**
- `InfrastructureName` (String)

**Resources:**
- EKS Cluster IAM Role (trust: eks.amazonaws.com)
  - Attached policies: AmazonEKSClusterPolicy, AmazonEKSVPCResourceController
- Worker Node IAM Role (trust: ec2.amazonaws.com)
  - Attached policies: AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy,
    AmazonEC2ContainerRegistryReadOnly
- Worker Instance Profile
- EBS CSI Driver IAM Role (trust: eks.amazonaws.com via OIDC)
  - Attached policy: AmazonEBSCSIDriverPolicy
  - Used by the EBS CSI add-on's service account

**Outputs:** EksClusterRoleArn, WorkerNodeRoleArn, WorkerInstanceProfileName,
EbsCsiDriverRoleArn

### 3. `security.yaml` -- Security Groups

**Parameters:**
- `InfrastructureName` (String)
- `VpcId` (AWS::EC2::VPC::Id)
- `VpcCidr` (String)

**Resources:**
- EKS Cluster Security Group
  - Ingress: HTTPS (443) from worker SG
- Worker Node Security Group
  - Ingress: all traffic from self (inter-node)
  - Ingress: HTTPS (443), kubelet (10250), DNS (53 tcp/udp), NodePort range
    (30000-32767) from cluster SG
  - Ingress: SSH (22) from VPC CIDR

**Outputs:** ClusterSecurityGroupId, WorkerSecurityGroupId

### 4. `eks_cluster.yaml` -- EKS Cluster

**Parameters:**
- `InfrastructureName` (String)
- `EksVersion` (String, default 1.30)
- `ClusterRoleArn` (String)
- `SubnetIds` (List)
- `ClusterSecurityGroupId` (String)

**Resources:**
- AWS::EKS::Cluster with:
  - Kubernetes version from config
  - VPC config with subnets and security group
  - Endpoint access: public + private
  - Control plane logging enabled

**Outputs:** ClusterName, ClusterEndpoint, ClusterCertificateAuthority,
ClusterOIDCIssuer

### 5. `worker_nodes.yaml` -- Self-Managed Worker Nodes

**Parameters:**
- `InfrastructureName` (String)
- `ClusterName` (String)
- `ClusterEndpoint` (String)
- `ClusterCertificateAuthority` (String)
- `WorkerInstanceType` (String, default c8i.2xlarge)
- `WorkerInstanceProfileName` (String)
- `WorkerSecurityGroupId` (String)
- `SubnetIds` (List)
- `KeyName` (String) -- EC2 key pair name for SSH
- `DesiredCapacity` (Number)
- `MinSize` (Number)
- `MaxSize` (Number)

**Resources:**
- Launch Template:
  - EKS-optimized Amazon Linux 2023 AMI (SSM parameter lookup)
  - Instance type from config
  - Security group
  - SSH key pair
  - User data (bootstrap.sh to join EKS cluster)
  - 120 GB gp3 root volume
  - Instance profile
  - Tags for cluster auto-discovery
- Auto Scaling Group:
  - Uses Launch Template
  - Spans worker subnets
  - Desired/min/max capacity from config

**Outputs:** WorkerAutoScalingGroupName

### 6. `addons.yaml` -- Essential EKS Add-ons

Installs the three add-ons required for a functional, accessible cluster.

**Parameters:**
- `ClusterName` (String)
- `EbsCsiDriverRoleArn` (String)

**Resources:**
- `AWS::EKS::Addon` -- **vpc-cni** (amazon-vpc-cni-k8s): Pod networking via
  ENIs. Required for pods to get IP addresses and communicate.
- `AWS::EKS::Addon` -- **coredns**: Cluster DNS. Required for service discovery
  (pods resolving Service names).
- `AWS::EKS::Addon` -- **kube-proxy**: Node-level network proxy. Required for
  Service routing (ClusterIP, NodePort, LoadBalancer).
- `AWS::EKS::Addon` -- **aws-ebs-csi-driver**: EBS CSI driver for persistent
  volumes. Required for any workload using PVCs backed by EBS.
- `AWS::EKS::Addon` -- **aws-mountpoint-s3-csi-driver**: Mount S3 buckets as
  filesystems in pods.

The EBS CSI driver requires IAM permissions to manage EBS volumes. The IAM
template will include an additional role for this with the
AmazonEBSCSIDriverPolicy managed policy, passed to the add-on via
`ServiceAccountRoleArn`.

All add-ons use `ResolveConflicts: OVERWRITE` so CloudFormation can manage them
cleanly, and `PRESERVE` on delete so destroying the stack doesn't break a
running cluster mid-teardown.

**Outputs:** VpcCniAddonArn, CoreDnsAddonArn, KubeProxyAddonArn,
EbsCsiAddonArn, S3CsiAddonArn

## What is NOT Included

- No Route53 DNS records (per user decision)
- No bootstrap nodes (not applicable to EKS)
- No control plane EC2 instances (EKS manages the control plane)
- No ingress controller setup (handled separately)

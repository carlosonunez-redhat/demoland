# Plan: k8s-eks provision.sh and destroy.sh

## Context

The `k8s-eks` environment has six CloudFormation templates ready
(`vpc`, `iam`, `security`, `eks_cluster`, `worker_nodes`, `addons`) but
`provision.sh` and `destroy.sh` are stubs. This plan fills them in
following the same patterns as `ocp-aws-upi`, using the existing CFN
helper functions from `include/helpers/aws.sh`.

---

## Files to create or modify

| File | Action |
|------|--------|
| `environments/k8s-eks/include/eks.sh` | **CREATE** -- EKS-specific helpers |
| `environments/k8s-eks/provision.sh` | **MODIFY** -- full provisioning flow |
| `environments/k8s-eks/destroy.sh` | **MODIFY** -- full teardown flow |
| `environments/k8s-eks/Containerfile` | **MODIFY** -- needs aws cli + kubectl |

No changes to `config.yaml`, `Justfile`, `include/helpers/aws.sh`, or
any `ocp-aws-upi` files.

---

## 1. `environments/k8s-eks/include/eks.sh` (new)

Defines EKS-specific helpers sourced by both provision and destroy scripts.

**Functions:**

- `_cluster_name()` -- required by `_create_cfn_stack()` in
  `include/helpers/aws.sh` (line 272). Reuses the same logic from
  `include/helpers/ocp.sh:1-6`: strips non-alphanumeric chars from the
  top-level env name, truncated to 18 chars.

- `_eks_infra_name()` -- derives the `InfrastructureName` parameter
  passed to all CFN templates. Combines `_cluster_name()` with
  `_get_this_environment_id()`, truncated to 27 chars (template regex
  constraint). Pattern mirrors `_ocp_cluster_name()` from
  `include/helpers/ocp.sh:8-13`.

- `_eks_version()` -- reads `.deploy.cluster_config.eks_version` from
  config; strips patch version for SSM AMI lookups (e.g. `1.30.1` ->
  `1.30`).

- `_eks_optimized_ami()` -- resolves the EKS-optimized AMI via
  `_exec_aws ssm get-parameter` on path
  `/aws/service/eks/optimized-ami/<version>/amazon-linux-2023/x86_64/standard/recommended/image_id`.
  Handles amd64/arm64 detection using `_aws_get_arch_from_instance_type()`
  from `include/helpers/aws.sh:292`.

- `_eks_kubeconfig_path()` -- returns
  `$(_get_file_from_data_dir 'eks-kubeconfig')`.

- `_generate_eks_kubeconfig()` -- runs
  `_exec_aws eks update-kubeconfig` to generate a kubeconfig at the
  above path.

- `_apply_aws_auth_configmap()` -- creates/updates the `aws-auth`
  ConfigMap in `kube-system` namespace so self-managed worker nodes can
  register with the cluster. Maps the WorkerNodeRoleArn (from IAM stack
  output) to `system:bootstrappers` and `system:nodes` groups.

---

## 2. `environments/k8s-eks/provision.sh`

Sources: `aws.sh`, `config.sh`, `data.sh`, `errors.sh`, `logging.sh`,
`yaml.sh` (from `$INCLUDE_DIR/helpers/`), plus `eks.sh` (from
`$ENVIRONMENT_INCLUDE_DIR/`).

**Sequential function call order:**

```
save_ssh_key                   # Extract SSH key from config secrets to /data
upload_key_into_ec2            # Import as EC2 key pair via _exec_aws
create_vpc                     # CFN: vpc.yaml
create_iam_roles               # CFN: iam.yaml (CAPABILITY_NAMED_IAM)
create_security_groups         # CFN: security.yaml
create_eks_cluster             # CFN: eks_cluster.yaml
generate_kubeconfig            # aws eks update-kubeconfig
apply_aws_auth_configmap       # kubectl: aws-auth ConfigMap for node join
create_worker_nodes            # CFN: worker_nodes.yaml
wait_for_nodes_ready           # Poll kubectl get nodes until all Ready
install_addons                 # CFN: addons.yaml (CAPABILITY_NAMED_IAM)
verify_cluster_access          # kubectl get nodes (final check)
```

**Key implementation details:**

- Each `create_*` function builds a params array, calls
  `_create_aws_cf_params_json`, then passes to
  `_create_aws_resources_from_cfn_stack` (or `_with_caps` for IAM).
  Pattern matches `ocp-aws-upi/provision.sh` functions like
  `create_vpc()` (line 265).

- `save_ssh_key` extracts the key from `.deploy.secrets.ssh_key.data`
  (already provided in config) and saves it to `/data/id_rsa` with
  mode 600. Does NOT generate a new key.

- `upload_key_into_ec2` imports the public key into EC2 via
  `_exec_aws ec2 import-key-pair`.

- `create_worker_nodes` needs dynamic AMI lookup via
  `_eks_optimized_ami()` (which uses `_exec_aws ssm get-parameter`)
  and computes DesiredCapacity as `quantity_per_zone * num_worker_azs`.

- `create_eks_cluster` combines public + private subnet IDs from the VPC
  stack as a comma-separated string for the `SubnetIds` parameter
  (CFN `List<AWS::EC2::Subnet::Id>` type).

- `install_addons` derives `OIDCIssuerHost` from the `OIDCIssuerUrl`
  output of the eks_cluster stack by stripping the `https://` prefix.

- `wait_for_nodes_ready` polls `kubectl get nodes` with a retry loop
  (up to 180 attempts, 1s apart) until all nodes show `Ready` status.
  Expected count = `quantity_per_zone * num_worker_azs`.

- `verify_cluster_access` is the final function; runs `kubectl get
  nodes` and logs success/failure. Returns non-zero on failure.

**Config paths used** (all via `_get_from_config`):

| Path | Used for |
|------|----------|
| `.deploy.cluster_config.eks_version` | EKS version |
| `.deploy.cloud_config.aws.networking.cidr_block` | VPC CIDR |
| `.deploy.cloud_config.aws.networking.region` | AWS region |
| `.deploy.cloud_config.aws.networking.availability_zones.*` | AZ lists |
| `.deploy.node_config.workers.quantity_per_zone` | Worker count |
| `.deploy.node_config.workers.instance_type` | Worker instance type |
| `.deploy.secrets.ssh_key.name` | EC2 key pair name |
| `.deploy.secrets.ssh_key.data` | SSH private key |

> **Prerequisite:** User will restructure `config.yaml` to move
> `node_config` and `secrets` from under `deploy.cloud_config` to
> directly under `deploy` (matching the `ocp-aws-upi` pattern) before
> these scripts run.

---

## 3. `environments/k8s-eks/destroy.sh`

Sources the same helpers as provision.sh.

**Sequential function call order (reverse of provision):**

```
delete_addons                  # CFN: delete addons stack
delete_worker_nodes            # CFN: delete worker_nodes stack
delete_eks_cluster             # CFN: delete eks_cluster stack
delete_security_groups         # CFN: delete security stack
delete_iam_roles               # CFN: delete iam stack
delete_vpc                     # CFN: delete vpc stack
delete_ec2_key_pair            # _exec_aws ec2 delete-key-pair
delete_ssh_key                 # Local: rm from /data
delete_kubeconfig              # Local: rm kubeconfig from /data
```

Each `delete_*` function uses `_delete_aws_resources_from_cfn_stack`
from `include/helpers/aws.sh:219`, passing the stack name and a
descriptive message. Pattern matches `ocp-aws-upi/destroy.sh`.

---

## 4. `environments/k8s-eks/Containerfile`

The container must have `aws` CLI and `kubectl`. Based on
`ocp-aws-upi/Containerfile`, extends `demoland-base`:

```dockerfile
FROM demoland-base AS final
RUN curl -L "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" \
      | bsdtar -C /tmp -xf - && \
    chmod -R +x /tmp/aws && /tmp/aws/install
RUN curl -LO "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

(Architecture detection needed for multi-arch support.)

---

## Decisions

1. **Config paths:** User will restructure `config.yaml` to move
   `node_config` and `secrets` to directly under `deploy` (matching
   `ocp-aws-upi`). Scripts will use `.deploy.node_config.*` and
   `.deploy.secrets.*` paths.

2. **Containerfile:** Will be filled in as part of this work.

---

## Verification

1. Review the generated scripts for correct CFN parameter wiring by
   cross-referencing each template's Parameters/Outputs sections.
2. Dry-run: `just deploy k8s-eks` in a test AWS account to verify the
   full provision -> verify flow.
3. Dry-run: `just destroy k8s-eks` to verify clean teardown.
4. Confirm `kubectl get nodes` returns the expected number of Ready
   nodes at the end of provisioning.

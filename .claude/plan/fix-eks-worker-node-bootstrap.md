# Fix EKS Worker Node Bootstrap (AL2023 nodeadm)

## Problem

Worker nodes aren't joining the EKS cluster because the UserData in
`worker_nodes.yaml` calls `/etc/eks/bootstrap.sh` (Amazon Linux 2), but the AMI
being resolved in `eks.sh` is an Amazon Linux 2023 image which uses `nodeadm`
instead.

## Plan

### 1. Update `worker_nodes.yaml` UserData

Replace the AL2-style `bootstrap.sh` call with the AL2023 MIME multipart
`nodeadm` NodeConfig format.

**File:** `environments/k8s-eks/include/cloudformation/worker_nodes.yaml`
**Lines:** 128-134

Change:
```yaml
UserData:
  Fn::Base64: !Sub |
    #!/bin/bash
    set -o xtrace
    /etc/eks/bootstrap.sh '${ClusterName}' \
      --apiserver-endpoint '${ClusterEndpoint}' \
      --b64-cluster-ca '${ClusterCertificateAuthority}'
```

To:
```yaml
UserData:
  Fn::Base64: !Sub |
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      cluster:
        name: ${ClusterName}
        apiServerEndpoint: ${ClusterEndpoint}
        certificateAuthority: ${ClusterCertificateAuthority}

    --BOUNDARY--
```

### 2. No other changes needed

- `eks.sh` — AMI resolution path (`amazon-linux-2023`) is correct; no change.
- `iam.yaml` — Worker node IAM policies are correct; no change.
- `security.yaml` — Security group rules are correct; no change.
- `provision.sh` — Orchestration order is correct (`aws-auth` applied before
  workers are created); no change.

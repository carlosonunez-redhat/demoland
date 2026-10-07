# Red Hat Multicluster Observability Demo

Understand platform-level behavior across all of your OpenShift clusters with
Advanced Cluster Management and Multicluster Observability.

<!-- vim-markdown-toc GFM -->

* [Three Key Points](#three-key-points)
* [Architecture](#architecture)
* [Setting Up](#setting-up)
    * [What You'll Need](#what-youll-need)
        * [Tools](#tools)
        * [OpenShift Clusters](#openshift-clusters)
        * [Non-OpenShift Kubernetes Clusters](#non-openshift-kubernetes-clusters)
    * [Instructions](#instructions)
        * [Organize OpenShift Kubeconfigs and create `oc` aliases](#organize-openshift-kubeconfigs-and-create-oc-aliases)
            * [Gather Cluster Admin Kubeconfig for your ACM Hub](#gather-cluster-admin-kubeconfig-for-your-acm-hub)
            * [Gather Cluster Admin Kubeconfig for your ROSA cluster](#gather-cluster-admin-kubeconfig-for-your-rosa-cluster)
            * [Gather Cluster Admin Kubeconfig for your "local observablity" cluster](#gather-cluster-admin-kubeconfig-for-your-local-observablity-cluster)
            * [Create a Cluster Admin Kubeconfig for your EKS cluster](#create-a-cluster-admin-kubeconfig-for-your-eks-cluster)
        * [Create S3 Bucket for Metrics Aggregation](#create-s3-bucket-for-metrics-aggregation)
        * [Install operators into ACM hub](#install-operators-into-acm-hub)
            * [Automatically](#automatically)
            * [Manually](#manually)
        * [Generate image pull secrets for (soon-to-be) managed clusters](#generate-image-pull-secrets-for-soon-to-be-managed-clusters)
        * [Import Demo Clusters into ACM](#import-demo-clusters-into-acm)
            * [Automatically](#automatically-1)
            * [Manually](#manually-1)
        * [Create auto-import secrets for OpenShift clusters](#create-auto-import-secrets-for-openshift-clusters)
        * [Finish importing the managed EKS cluster](#finish-importing-the-managed-eks-cluster)
        * [Install Multi-Cluster Observability](#install-multi-cluster-observability)
            * [Automatically](#automatically-2)
            * [Manually](#manually-2)
        * [Finish Multi-Cluster Observability Installation](#finish-multi-cluster-observability-installation)
        * [Install OpenShift Lightspeed](#install-openshift-lightspeed)
        * [Install test apps](#install-test-apps)
* [Demo](#demo)
    * [Visualizing cluster behavior with Grafana](#visualizing-cluster-behavior-with-grafana)
    * [Viewing automated right-sizing recommendations from ACM Observability](#viewing-automated-right-sizing-recommendations-from-acm-observability)
    * [Chatting with your infrastructure with OpenShift Lightspeed](#chatting-with-your-infrastructure-with-openshift-lightspeed)
* [Next Steps](#next-steps)

<!-- vim-markdown-toc -->

## Three Key Points

- Visualize behavior across multiple clusters with **Grafana** and
  **Prometheus** metrics aggregated by **Thanos**, all out of the box.
- Use `RightSizingRecommendation` resources to implement capacity management
  baselines.
- Chat with your observability platform with your favorite AI model with
  **OpenShift Lightspeed for ACM**.

## Architecture

> 🚧 **Work In Progress**
>
> This architecture image is from the ACM documentation. It will be updated as
> this environment is built out.

![](./include/assets/img/architecture.png)

This demo contains three clusters: a self-managed OpenShift cluster on AWS, a
Red Hat-managed OpenShift cluster, also in AWS, and a regular Kubernetes cluster
served by AWS EKS.

All of these clusters are managed by an OpenShift cluster running Red Hat
Advanced Cluster Management. (This will be called the "multicluster hub" or just
"the hub" throughout this demo.)

The self-managed OpenShift cluster managed by the hub is an instance of the
local-cluster observability demo located [here](../rhobs-demo/README.md).

Timeseries metrics from each cluster are aggregated
by a Thanos instance that is deployed and automatically configured by the
Multicluster Observability Operator running on the hub. (ACM installs an
instance of Prometheus on the EKS cluster to retrieve cluster metrics from it.)

AI-driven Observability is enabled by OpenShift Lightspeed. Lightspeed
automatically installs the OpenShift MCP Serer which, amongst other things, can
pull observability signals from Thanos. The self-managed OpenShift cluster also
contains an instance of Lightspeed to enable local AI-driven observability there
as well.

## Setting Up

### What You'll Need

#### Tools

- A shell, like `bash`, `zsh` or `fish`

#### OpenShift Clusters

- An OpenShift cluster running ACM (tested with OpenShift 4.20.14 and ACM 2.16)
- An OpenShift cluster running on Red Hat OpenShift for AWS (ROSA)
- (Optional) An OpenShift cluster running the "Red Hat Observability" demo
  documented
  [here](https://github.com/redhat-na-ssa/demo-cluster-observability-rhobs)

#### Non-OpenShift Kubernetes Clusters

- An EKS Cluster (this demo was tested with Kubernetes v1.31)

> 📝 **NOTE**
>
> You can also use [Carlos's Demoland](https://github.com/carlosonunez-redhat/demoland) to spin up
> everything you'll need to run this demo in about 90 minutes. (45 minutes for
> the ACM hub and 45 minutes for the two clusters it will manage.)

### Instructions

#### Organize OpenShift Kubeconfigs and create `oc` aliases

Since we'll be working with several Kubernetes clusters in this demo, let's
begin by organizing all of the **Cluster Admin** Kubeconfigs that we will be using into one place
and setting up `oc` and `kubectl` aliases that will reference them.

##### Gather Cluster Admin Kubeconfig for your ACM Hub

```sh
oc login https://acm-hub.example.com --username=kubeadmin --password=$KUBEADMIN_PASSWORD &&
  cat ~/.kube/config > /tmp/acm.kubeconfig &&
  rm ~/.kube/config
alias oc_acm='oc --kubeconfig /tmp/acm.kubeconfig'
```

##### Gather Cluster Admin Kubeconfig for your ROSA cluster

```sh
oc login https://rosa.example.com --web &&
  cat ~/.kube/config > /tmp/rosa.kubeconfig &&
  rm ~/.kube/config
alias oc_rosa='oc --kubeconfig /tmp/rosa.kubeconfig
```

##### Gather Cluster Admin Kubeconfig for your "local observablity" cluster

> 📝 Skip this step if you did not provision the Red Hat Observability demo
> cluster.

```sh
oc login https://rhobs.example.com --web &&
  cat ~/.kube/config > /tmp/rhobs.kubeconfig &&
  rm ~/.kube/config
alias oc_rhobs='oc --kubeconfig /tmp/rhobs.kubeconfig
```

##### Create a Cluster Admin Kubeconfig for your EKS cluster

Run the command below to generate a cluster-admin Kubeconfig that will use
short-lived tokens generated by the AWS CLI to authenticate:

```sh
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME \
  --kubeconfig /tmp/eks.kubeconfig
alias oc_eks='kubectl --kubeconfig /tmp/eks.kubeconfig'
alias kubectl_eks='kubectl --kubeconfig /tmp/eks.kubeconfig'
```

If you don't want to use the AWS CLI in your EKS kubeconfig, you'll need to
create a Kubernetes Service Account that's bound to the `cluster-admin` Cluster
Role and create the Kubeconfig yourself. Click
[here](https://claude.ai/share/62e7c27e-af20-4f78-86c2-b86a26462ea7) to see a
Claude chat that describes how to do this.

#### Create S3 Bucket for Metrics Aggregation

The ACM hub in our demo environment will use the Multicluster Observability
Operator (MCO) to display the health and high-level activity of the OpenShift and EKS
clusters that it will manage. MCO uses Thanos to aggregate the cluster metrics
used to enable this capability.

Thanos uses an S3 bucket to deposit these metrics and other metadata. Use the
CloudFormation template provided by this demo to deploy it:

```sh
aws cloudformation create-stack \
  --stack-name thanos-s3-bucket \
  --capabilities CAPABILITY_NAMED_IAM \
  --template-body ./include/cloudformation/thanos_s3_bucket \
  --parameters '{}'
```

#### Install operators into ACM hub

Next, we'll need to install the operators shown below into our ACM hub:

- Advanced Cluster Management
- Multi-Cluster Engine
- OpenShift Lightspeed

##### Automatically

Run the command below to install these operators automatically:

```sh
oc_acm apply -k bootstrap/operators
```

Afterwards, run the command below to wait for the ACM console to become
available:

```bash
while test "$attempts" -lt 60
do
  pods=$(oc_acm -n multicluster-engine get pod -l app=console-mce -o name)
  test -n "$pods" && break
  info "[${attempts}/60] Waiting for ACM Pods to be created..."
  sleep 0.5
  attempts=$((attempts+1))
done
if test -z "$pods"
then
  error "ACM never started."
  return 1
fi
for pod in $pods
do
  info "Waiting 180 seconds for ACM console Pod '$pod' to become ready..."
  &>/dev/null oc_acm wait -n multicluster-engine --for=condition=Ready --timeout=180s "$pod" && continue
  error "ACM console Pod '$pod' failed to become ready."
done
```

##### Manually

The installation process for all of these operators is the same. Repeat the
steps below for each of the operators on this list.

1. From the OpenShift console, click on **Ecosystem**, then on **Software
   Catalog** to view the list of operators available in your cluster.

![](./include/assets/img/ecosystem.png)

2. Search for the operator to install, then click on "Install." Review the
   defaults presented, then click on "Install" to complete the installation.

3. The OpenShift Console will notify you when the operator has been installed.

![](./include/assets/img/ecosystem-complete.png)

You'll be logged out of the console a few minutes after the operator finishes
installing. Log in again when this happens. After logging in, you'll notice a
"Fleet Management" drop-down near the upper-left-hand corner of the page.

![](./include/assets/img/fleet-management.png)

If you see this, then ACM has been installed successfully and is ready for use.

#### Generate image pull secrets for (soon-to-be) managed clusters

We will need to generate an OpenShift pull secret that the Open Cluster
Management (OCM) agent installed by ACM and its Observability add-on will use to
pull its container images.

Run the command below to do that:

```sh
pull_secret=$(oc_acm get secret/pull-secret -n openshift-config \
    --template='{{index .data ".dockerconfigjson" | base64decode}}'
oc_acm create secret -n advanced-cluster-management generic \
    image-pull-secret \
    --from-literal=.dockerconfigjson="$pull_secret" \
    --type=kubernetes.io/dockerconfigjson
oc_acm create secret -n advanced-cluster-management-mce generic \
    rh-pull-secret \
    --from-literal=.dockerconfigjson="$pull_secret" \
    --type=kubernetes.io/dockerconfigjson
```

#### Import Demo Clusters into ACM

We're now ready to import our demo clusters.

##### Automatically

```sh
# Create a ManagedClusterSet to group our clusters with...
oc_acm apply -k bootstrap/resources/clustersets

# ...then import the clusters. They won't be ready until we
# create their auto-import secrets, which we'll do in the next
# section.
for cluster_type in eks rosa
do oc_acm apply -k "bootstrap/imported-clusters/$cluster_type"
done

read -p "Did you deploy the Red Hat Observability demo cluster? (yes/NO): "
choice
test "${choice,,}" == yes && oc_acm apply -k bootstrap/imported-clusters/rhobs
```

##### Manually

First, create a `ManagedClusterSet` that ACM can use to easily identify them
with:

```sh
oc_acm apply -f - <<-EOF
apiVersion: cluster.open-cluster-management.io/v1beta2
kind: ManagedClusterSet
metadata:
  name: imported-clusters
EOF
```

Next,  use the command below to import our clusters. Since these clusters are being "auto-imported", we
will need to create "auto-import" secrets for each one before ACM can
successfully manage them. We'll do that in the next step.

```sh
cluster_types="eks rosa"
read -p "Did you deploy the Red Hat Observability demo cluster? (yes/NO): "
choice
test "${choice,,}" == yes && cluster_types="${cluster_types} rhobs"
for cluster_type in $cluster_types
do oc_acm apply -f - <<-EOF
apiVersion: v1
kind: Namespace
metadata:
  name: imported-cluster-$cluster_type
---
apiVersion: agent.open-cluster-management.io/v1
kind: KlusterletAddonConfig
metadata:
  name: imported-cluster-$cluster_type
  namespace: imported-cluster-$cluster_type
spec:
  applicationManager:
    enabled: true
  certPolicyController:
    enabled: true
  policyController:
    enabled: true
  searchCollector:
    enabled: true
---
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  labels:
    cloud: auto-detect
    cluster.open-cluster-management.io/clusterset: imported-clusters
    imported: "true"
    name: imported-cluster-$cluster_type
    vendor: auto-detect
  name: imported-cluster-$cluster_type
spec:
  hubAcceptsClient: true
EOF
done
```

#### Create auto-import secrets for OpenShift clusters

Next, create the auto-import secrets that ACM will need to manage our imported
OpenShift clusters. (Our EKS cluster will be "manually" imported with a
Kubernetes secret, which we'll do in the next section.)

```sh
cluster_types="rosa"
read -p "Did you deploy the Red Hat Observability demo cluster? (yes/NO): "
choice
test "${choice,,}" == yes && cluster_types="${cluster_types} rhobs"
for cluster_type in $cluster_types
do
    cmd="oc_${cluster_type}"
    enc_kubeconfig=$(base64 -w 0 < "/tmp/${cluster_type}.kubeconfig")
    "$cmd" apply -f - <<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: auto-import-secret
  namespace: imported-cluster-$cluster_type
  managedcluster-import-controller.open-cluster-management.io/keeping-auto-import-secret: ""
stringData:
  kubeconfig: $enc_kubeconfig
EOF
done
```

#### Finish importing the managed EKS cluster

Since automatic cluster import is an OpenShift-specific feature, we'll need to
manually finish importing the EKS cluster by applying the
automatically-generated Kubernetes manifests that will install the OCM agent and
connect it to our ACM hub.

First, create the Kubernetes Custom Resources for the OCM agent:

```sh
oc_acm get secret imported-cluster-eks-import \
    -n imported-cluster-eks \
    -o jsonpath='{.data.crds\\.yaml}' | base64 --decode |
    oc_eks apply -f -
```

Afterwards, create the OCM agent resources:

```sh
oc_acm get secret imported-cluster-eks-import \
    -n imported-cluster-eks \
    -o jsonpath='{.data.import\\.yaml}' | base64 --decode |
    oc_eks apply -f -
```

Wait a minute or two, then run the command below to query the state of the
managed EKS cluster. The "Joined" property should be `True`:

```sh
oc_acm get managedcluster imported-cluster-eks
```

#### Install Multi-Cluster Observability

With all of our clusters being managed by ACM, we're now ready to configure
Multi-Cluster Observability.

##### Automatically

```sh
oc_acm apply -k bootstrap/resources/observability
```

##### Manually

Create a namespace for our multi-cluster observability resources:

```sh
oc_acm apply -f - <<-EOF
apiVersion: v1
kind: Namespace
metadata:
  name: open-cluster-management-observability
EOF
```

Afterwards, configure the
`MultiClusterObservability` installation resource that will deploy Thanos,
Observatorium, Grafana and modifications to the Fleet Management console:

```sh
oc_acm apply -f - <<-EOF
apiVersion: observability.open-cluster-management.io/v1beta2
kind: MultiClusterObservability
metadata:
  name: observability
spec:
  observabilityAddonSpec: {}
  storageConfig:
    metricObjectStorage:
      key: thanos.yaml
      name: thanos-object-storage
EOF
```

You should see Pods within the
`open-cluster-management-observability` namespace in a minute or two. They won't
be ready yet:

```sh
oc_acm get pods -n open-cluster-management-observability
```

#### Finish Multi-Cluster Observability Installation

Create the Thanos configuration secret to complete the installation:

```sh
bucket=$(aws cloudformation describe-stacks --stack-name thanos-s3-bucket \
  --query 'Stacks[0].Outputs[?Key==`BucketName`].OutputValue' \
  --output text)
bucket_access_key=$(aws cloudformation describe-stacks --stack-name thanos-s3-bucket \
  --query 'Stacks[0].Outputs[?Key==`AccessKey`].OutputValue' \
  --output text)
bucket_secret_key=$(aws cloudformation describe-stacks --stack-name thanos-s3-bucket \
  --query 'Stacks[0].Outputs[?Key==`SecretAccessKey`].OutputValue' \
  --output text)
oc_acm apply -f - <<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: thanos-object-storage
  namespace: open-cluster-management-observability
type: Opaque
stringData:
  thanos.yaml: |
    type: s3
    config:
      bucket: $bucket
      endpoint: s3.$(aws configure get region).amazonaws.com
      insecure: true
      access_key: $bucket_access_key
      secret_access_key: $bucket_secret_key
EOF
```

Next, create a pull secret that will be pushed into managed clusters for their
Observability add-ons:

```sh
pull_secret=$(oc_acm get secret/pull-secret -n openshift-config \
    --template='{{index .data ".dockerconfigjson" | base64decode}}'
oc_acm create secret -n open-cluster-management-observability generic \
    image-pull-secret \
    --from-literal=.dockerconfigjson="$pull_secret" \
    --type=kubernetes.io/dockerconfigjson
```

Next, use the `watch` command to see MCO Pods become Ready. All of the Pods
in the namespace **must** be ready in order for MCO to become ready and
fully-operational:

```sh
watch -n 0.5 oc_acm get pods -n open-cluster-management-observability
```

Finally (or simultaneously), wait for the observability add-on to become ready in the EKS cluster:

```sh
oc_acm wait -n imported-cluster-eks \
    --for jsonpath='{.status.conditions[?(@.type=="Available")].status}=True' \
    mca observability-controller --timeout=600s
```

#### Install OpenShift Lightspeed

Almost done! We're now going to deploy OpenShift Lightspeed into the ACM hub and
the Red Hat Observability cluster (if deployed) to use AI to gather
insights about our cluster.

> 📝 Make sure to repeat these steps for the OpenShift cluster running the
> Red Hat Observability demo if you deployed it.

> 📝 Replace all references to `oc` in the docs linked below with `oc_acm`
> to apply changes to the ACM hub.

First, create a Secret that will hold the credentials for the LLM provider that
you wish to use. Use the instructions provided by our docs
[here](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-configuring-openshift-lightspeed#ols-creating-the-credentials-secret-using-cli_ols-configuring-openshift-lightspeed).

Next, create the `OLSConfig` resource that will deploy OpenShift Lightspeed
resources. Use the instructions provided by our docs
[here](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/html/configure/ols-configuring-openshift-lightspeed#ols-creating-the-credentials-secret-using-cli_ols-configuring-openshift-lightspeed)
to guide you through this. Make sure that `credentialsKey` in your provider
configuration is set to `apitoken` per the docs linked by the previous step.

Finally, use `oc` to wait for Pods in the `openshift-lightspeed` namespace to
become available. All Pods must be Running and ready in order for Lightspeed to
be fully-operational:

```sh
watch -n 0.5 oc_acm get pods -n openshift-lightspeed
```

#### Install test apps

Finally, install the test apps used within this demo into your clusters.

```sh
oc_rosa apply -k bootstrap/apps
oc_eks apply -k bootstrap/apps
```

## Demo

You are a platform engineer that is responsible for multiple OpenShift and
Kubernetes clusters across your organization. Understanding how applications
interact with each other across and between these clusters is important.

While your organization has many products to help achieve this (Datadog, Splunk,
maybe even New Relic still), the bill for maintaining these services is only
getting more expensive.

There is an increasing appetite to roll a homegrown observability platform.
However, the thought of architecting, configuring and supporting all of the
tools you'll need to get this done --- Grafana, Prometheus, Thanos, Loki, OTel,
etc. --- is daunting, and that's before considering approvals from the
architecture review board or enterprise support options.

In addition to providing fleet management capabilities for OpenShift and
Kubernetes clusters, Advanced Cluster Management provides a simple way for
administrators to set up a production-level observability platform with minimal
overhead or toil. Everything that's shown in this demo comes out of the box and
can be configured from our documentation alone.

Let's take a closer look.

![](./assets/img/0-acm-start.png)

![](./assets/img/1-acm-mco-top-consumers-multicluster.png)

![](./assets/img/2-acm-mco-overestimation.png)

![](./assets/img/3-acm-mco-overestimation-zoomin-rhobs.png)

![](./assets/img/4-acm-mco-dashboards-rightsizing.png)

![](./assets/img/5-acm-mco-explore-with-query.png)

![](./assets/img/5-acm-mco-rightsize-recommended-cpu.png)

![](./assets/img/6-acm-mco-rightsize-memory.png)

![](./assets/img/7-acm-mco-alerts.png)

![](./assets/img/8-acm-mco-high-cpu-rhobs.png)

![](./assets/img/9-acm-lightspeed-cpu-high-ask.png)

![](./assets/img/9-acm-lightspeed-it-found-it.png)

![](./assets/img/10-acm-lightspeed-fix-recommendations.png)

![](./assets/img/11-acm-console-linkout.png)

![](./assets/img/12-rhobs-pod-namespace.png)

![](./assets/img/13-rhobs-lightspeed-fix-pod.png)

![](./assets/img/14-rhobs-lightspeed-approve-fix.png)

![](./assets/img/15-rhobs-lightspeed-detected-gitops.png)

![](./assets/img/16-rhobs-app-pods.png)

![](./assets/img/17-rhobs-coo-related-resources.png)

![](./assets/img/18-rhobs-signal-correlation.png)

![](./assets/img/19-rhobs-coo-signal-correlation-source.png)

![](./assets/img/20-rhobs-coo-signal-correlation-logs.png)

![](./assets/img/21-rhobs-coo-signal-correlation-metrics.png)

![](./assets/img/22-rhobs-coo-tempo-traces.png)

![](./assets/img/23-rhobs-lightspeed-logging-stack.png)

![](./assets/img/24-rhobs-lightspeed-clf-lokistack.png)

![](./assets/img/25-rhobs-lightspeed-metrics-stack-query.png)

![](./assets/img/26-rhobs-lightspeed-otel-collector-found.png)

![](./assets/img/27-rhobs-otel-start.png)

![](./assets/img/28-rhobs-lightspeed-exporters.png)

![](./assets/img/29-rhobs-lightspeed-kafka-console.png)

![](./assets/img/30-streams-start.png)

![](./assets/img/31-streams-logs.png)

![](./assets/img/32-streams-traces.png)


### Visualizing cluster behavior with Grafana

### Viewing automated right-sizing recommendations from ACM Observability

### Chatting with your infrastructure with OpenShift Lightspeed

## Next Steps

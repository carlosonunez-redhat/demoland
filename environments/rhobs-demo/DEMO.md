# Red Hat Observability Demo

Easily observe your cluster and its workloads within the cluster and from within
your own observability stack.

## Three Key Points

- Observe cluster and workload behavior with minimal configuration with the
  **Red Hat Cluster Observability Operator (COO)**
- Aggregate and forward logs to your corporate log aggregators or SIEMs with the
  **Red Hat Cluster Logging Operator (COO)**
- Send workload and cluster signals to your existing observability stack with
  the **Red Hat Build of OpenTelemetry**

## Setting Up

> **NOTE**: You'll need access to an OpenShift cluster to install the components
> of this demo. Use the [Red Hat Sandbox](https://sandbox.redhat.com),
> [OpenShift Local](https://developers.redhat.com/products/openshift-local) or
> quickly stand up a Single-Node OpenShift cluster
> with [Carlos's Demoland](https://github.com/carlosonunez-redhat/demoland).

### Express

Install the OpenShift GitOps operator from the **Ecosystem > Software Catalog** pane
using the defaults.

![](../../assets/img/ecosystem-gitops.png)
![](../../assets/img/ecosystem-gitops-confirm.png)

Once the installation is complete, run the commands below to create an
application that installs the operators and components used by this demo:

#### Red Hat Observability Operators

```sh
# Remember to run `oc login` first before running the command(s) below
cat <<-EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhobs-demo-operators
  namespace: openshift-gitops
spec:
  project: default
  destination:
    namespace: openshift-gitops
    server: https://kubernetes.default.svc
  source:
    repoURL: https://github.com/carlosonunez-redhat/demoland
    targetRevision: main
    path: ./environments/rhobs-demo/bootstrap/operators
  syncPolicy:
    automated:
      enabled: true
    syncOptions:
      - SkipDryRunOnMissingResources=true
EOF
```

#### Red Hat Observability Resources

```sh
# Remember to run `oc login` first before running the command(s) below
cat <<-EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhobs-demo-resources
  namespace: openshift-gitops
spec:
  project: default
  destination:
    namespace: openshift-gitops
    server: https://kubernetes.default.svc
  source:
    repoURL: https://github.com/carlosonunez-redhat/demoland
    targetRevision: main
    path: ./environments/rhobs-demo/bootstrap/resources
  syncPolicy:
    automated:
      enabled: true
    syncOptions:
      - SkipDryRunOnMissingResources=true
EOF
```

#### Sample Applications

```sh
# Remember to run `oc login` first before running the command(s) below
cat <<-EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhobs-demo-apps
  namespace: openshift-gitops
spec:
  project: default
  destination:
    namespace: openshift-gitops
    server: https://kubernetes.default.svc
  source:
    repoURL: https://github.com/carlosonunez-redhat/demoland
    targetRevision: main
    path: ./environments/rhobs-demo/bootstrap/apps
  syncPolicy:
    automated:
      enabled: true
    syncOptions:
      - SkipDryRunOnMissingResources=true
EOF
```

The environment will be ready in about 15 minutes.

### Local

#### Install Operators

The observability stack in this demo will take advantage of these operators:

- **Red Hat Cluster Observability Operator**: Installs a complete observability
  stack (logging, metrics, and tracing) with OpenShift Console UI plugins for
  local observability.
- **Red Hat Cluster Logging Operator (CLO)**: Installs
  [Vector](https://github.com/vectordotdev/vector), a high-performance metrics
  forwarder, and enables centralized configuration and customization.
- **Red Hat Build of OpenTelemetry (OTel)**: Provides high-performance,
  low-latency signal collection, transformation and export with
  enterprise-friendly defaults.


We will also use these operators to simulate external systems often found in
enterprise observability platforms:

- **Streams for Apache Kafka**: A Kubernetes-native platform for microservices
  communication with Kafka. We'll be focusing on Kafka primitives (mostly
  topics) in this demo.
- **Splunk Enterprise**: The log aggregation platform for the enterprise.

The installation process for these operators is the same. Repeat the steps below
for each of the operators on this list.

1. From the OpenShift console, click on **Ecosystem**, then on **Software
   Catalog** to view the list of operators available in your cluster.

![](./assets/img/ecosystem.png)

2. Search for the operator to install, then click on "Install." Review the
   defaults presented, then click on "Install" to complete the installation.

3. The OpenShift Console will notify you when the operator has been installed.

![](./assets/img/ecosystem-complete.png)

#### Setting up Red Hat Observability


## Demos

### Observe cluster and workload behavior with COO



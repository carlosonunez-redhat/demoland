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

### The Express Lane

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

### The Scenic Route

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
- **Perses**: An open-source, CNCF-sponsored dashboard tool for metrics, logs and traces.

The installation process for all of these operators is the same. Repeat the
steps below for each of the operators on this list.

1. From the OpenShift console, click on **Ecosystem**, then on **Software
   Catalog** to view the list of operators available in your cluster.

![](./assets/img/ecosystem.png)

2. Search for the operator to install, then click on "Install." Review the
   defaults presented, then click on "Install" to complete the installation.

3. The OpenShift Console will notify you when the operator has been installed.

![](./assets/img/ecosystem-complete.png)

#### Enabling Cluster Platform Monitoring

Every OpenShift cluster ships with the **OpenShift Monitoring operator**. This
operator is responsible for installing Prometheus and Thanos and enabling node
exporters that expose cluster and workload metrics.

Cluster monitoring is not enabled by default. To enable it, create a special
`ConfigMap` in the `openshift-monitoring` namespace called
`cluster-monitoring-config` with an empty `config.yaml` key in its `data` field.

```sh
oc apply -f - <<-EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: ""
```

Wait a minute for the OpenShift Monitoring operator to apply the new
changes. Afterwards, visit the OpenShift console and click on **Observe** >
**Metrics**. Click on the dropdown underneath **Queries** and select **CPU
Usage**. A line graph of CPU usage for all workloads in the cluster should
appear along with a tabular outline of this data.

![](./assets/img/metrics.png)

**NOTE**: The **Cluster Observability Operator** provides the
**MonitoringStack** resource to configuring separate Prometheus instances to
better isolate metrics by workload or application domain. This is out of scope
for this demo, but you can learn more about this custom resource
[here](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/pdf/installing_red_hat_openshift_cluster_observability_operator/configuring-the-cluster-observability-operator-to-monitor-a-service#creating-a-monitoringstack-object-for-cluster-observability-operator_configuring_the_cluster_observability_operator_to_monitor_a_service).

#### Create namespaces

This environment uses three namespaces:

- **openshift-observability**: Hosts Tempo and the OpenTelemetry collector.
- **openshift-logging**: Hosts Loki and the ClusterLogForwarder that ships logs
  to Kafka, our external signals gathering system.
- **rhobs-messaging**: Hosts our "external" Kafka cluster.

Use `oc` to create them:

```sh
for ns in openshift-observability openshift-logging rhobs-messaging
do oc create ns "$ns"
done
```

Because our OpenTelemetryCollector will surface cluster metrics and node logs,
we will need to modify our `openshift-observability` namespace to allow
privileged pods. Use `oc` to do this as well:

```sh
oc annotate ns openshift-observability  \
  security.openshift.io/scc.podSecurityLabelSync="false" \
  pod-security.kubernetes.io/enforce="privileged" \
  pod-security.kubernetes.io/audit="privileged" \
  pod-security.kubernetes.io/warn="privileged"
```

#### Create service accounts

Next, we will create two service accounts:

- A service account that will enable the OpenTelemetry collector to collect
  cluster metrics, events and logs and publish traces to the cluster's Tempo
  instance, and
- A service account that enables Vector to retrieve cluster and workload logs
  through the ClusterLogForwarder.

##### OpenTelemetry Collector and Tempo

Create a `ServiceAccount` called `rhobs-sa`:

```sh
oc apply -f - <<-EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rhobs-sa
  namespace: openshift-observability
EOF
```

Next, use  a `ClusterRoleBinding` to allow this service account to create
privileged pods (required for surfacing node logs):

```sh
oc apply -f - <<-EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rhobs-sa-allow-privileged
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:openshift:scc:privileged
subjects:
- kind: ServiceAccount
  name: rhobs-sa
  namespace: openshift-observability
EOF
```

Next, create a `ClusterRole` to give this service account the ability to
retrieve Kubernetes resource information thorugh the Downward API, and create a
`ClusterRoleBinding` to assign this role to our service account:

```sh
oc apply -f - <<-EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: otel-collector
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rhobs-sa-assign-otel-collector-role
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: otel-collector
subjects:
- kind: ServiceAccount
  name: rhobs-sa
  namespace: openshift-observability
EOF
```

Finally, we need to give `rhobs-sa` the ability to log into Tempo so that our
OpenTelemetry collector can forward traces into it. Repeat the process above to
create a `ClusterRole` and `ClusterRoleBinding` that enables this capability:

```sh
oc apply -f - <<-EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tempo-allow-trace-write
rules:
- apiGroups:
  - 'tempo.grafana.com'
resources: 
  - cluster
resourceNames:
  - traces
verbs:
  - 'create' 
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rhobs-sa-assign-otel-collector-role
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tempo-allow-trace-write
subjects:
- kind: ServiceAccount
  name: rhobs-sa
  namespace: openshift-observability
EOF
```

##### LokiStack and Cluster Log Forwarder

Like the last section, start by creating a `ServiceAccount` for the Loki
instance that will hold our logs internally:

```sh
oc apply -f - <<-EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: collector
  namespace: openshift-logging
EOF
```

The OpenShift Cluster Logging Operator will create Cluster Roles that enable
service accounts to obtain application, infrastructure and audit logs from our
cluster and persist them into Loki.

Create a `ClusterRoleBinding` to assign these roles to our `collector`
service account:

```sh
oc apply -f - <<-EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: collect-audit-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-audit-logs
subjects:
- kind: ServiceAccount
  name: collector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: collect-infrastructure-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-infrastructure-logs
subjects:
- kind: ServiceAccount
  name: collector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: collect-application-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-application-logs
subjects:
- kind: ServiceAccount
  name: collector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: logging-collector-logs-writer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: logging-collector-logs-writer
subjects:
- kind: ServiceAccount
  name: collector
  namespace: openshift-logging
EOF
```

## Demos

### Observe and Forward Cluster Behavior with COO and OpenTelemetry



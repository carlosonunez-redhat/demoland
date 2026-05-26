# Quick Start: Integrating the Red Hat Build of OpenTelemetry with Kafka

## Scenario

![](../../assets/img/kafka.png)

Your observability stack uses Kafka to route metrics, logs and traces to
external observability systems. Each signal is sent to its respective Kafka
topic, and observability systems subscribe to each topic to receive and process
signals as they come in.

This quick start will guide you through configuring the Red Hat Build of
OpenTelemetry to send signals to Kafka and be compatible with this architecture.

## Prerequisites

- Working Kafka cluster (use [Streams for Apache
  Kafka](https://developers.redhat.com/products/streams-for-apache-kafka) for a
  test installation)
- Three Kafka topics:
    - `metrics-topic`
    - `logs-topic`
    - `traces-topic`

## Procedure

### Installation

1. Install the Red Hat Build of OpenTelemetry either [from the web
   console](https://docs.redhat.com/en/documentation/red_hat_build_of_opentelemetry/3.9/html/installing_red_hat_build_of_opentelemetry/install-otel#installing-otel-by-using-the-web-console_install-otel)
   or [with the
   CLI](https://docs.redhat.com/en/documentation/red_hat_build_of_opentelemetry/3.9/html/installing_red_hat_build_of_opentelemetry/install-otel#installing-otel-by-using-the-cli_install-otel).

2. Use the `oc` command below to create an OpenShift project for the
   OpenTelemetry collector:

   ```sh
   oc create ns otel
   ```

2. Use the YAML below to create a new `OpenTelemetryCollector` CR that sends
   metrics, logs and traces to Kafka and the `debug` exporter. 

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: collector-k8sobj
  namespace: otel
rules:
- apiGroups:
  - ""
  resources:
  - events
  - pods
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - "events.k8s.io"
  resources:
  - events
  verbs:
  - watch
  - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: collector
subjects:
  - kind: ServiceAccount
    name: collector
    namespace: otel
roleRef:
  kind: ClusterRole
  name: collector-k8sobj
  apiGroup: rbac.authorization.k8s.io
---
```

### Verification

Use the `oc logs` command below to confirm that the `collector` is receiving
metrics and logs from your Kubernetes cluster:

```sh
oc logs -n otel deployment/collector
```

You should see output similar to the below:

```
StartTimestamp: 2026-05-26 17:36:19.247048691 +0000 UTC
Timestamp: 2026-05-26 18:25:19.478362506 +0000 UTC
Value: 1
Metric #3
Descriptor:
     -> Name: k8s.container.restarts
     -> Description: How many times the container has restarted in the recent past. This value is pulled directly from the K8s API and the value can go indefinitely high and be reset to 0 at any time depending on how your kubelet is configured to prune dead containers. It is best to not depend too much on the exact value but rather look at it as either == 0, in which case you can conclude there were no restarts in the recent past, or > 0, in which case you can conclude there were restarts in the recent past, and not try and analyze the value beyond that.
     -> Unit: {restart}
     -> DataType: Gauge
NumberDataPoints #0
StartTimestamp: 2026-05-26 17:36:19.247048691 +0000 UTC
Timestamp: 2026-05-26 18:25:19.478362506 +0000 UTC
Value: 4
ResourceMetrics #11
Resource SchemaURL: https://opentelemetry.io/schemas/1.18.0
Resource attributes:
     -> k8s.pod.uid: Str(4237ee74-c6ea-4aff-a792-56614e5559a8)
     -> k8s.pod.name: Str(cluster-baremetal-operator-5d44678794-8rvkh)
     -> k8s.node.name: Str(ip-10-0-3-109.us-east-2.compute.internal)
     -> k8s.namespace.name: Str(openshift-machine-api)
     -> container.id: Str(f91a4d3ef4a7d1441a2d6a3a13b656c1b07f3c82ded527278b5d55712f812788)
     -> k8s.container.name: Str(baremetal-kube-rbac-proxy)
     -> container.image.name: Str(quay.io/openshift-release-dev/ocp-v4.0-art-dev)
     -> container.image.tag: Str(latest)
     -> k8s.pod.start_time: Str(2026-05-26T15:29:27Z)
     -> k8s.deployment.name: Str(cluster-baremetal-operator)
ScopeMetrics #0
ScopeMetrics SchemaURL:
InstrumentationScope github.com/open-telemetry/opentelemetry-collector-contrib/receiver/k8sclusterreceiver 0.144.0
Metric #0
Descriptor:
     -> Name: k8s.container.cpu_request
     -> Description: Resource requested for the container. See https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.23/#resourcerequirements-v1-core for details
     -> Unit: {cpu}
     -> DataType: Gauge
```

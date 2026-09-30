## Why

## How it works

Demolands are comprised of **base infrastructure** and **demo environments**.

### Base Infrastructure

**Base infrastructure** is the infrastructure on which demo environments are
served, like OpenShift and AAP.

<b><u>Criteria</u></b>

* Does NOT have a `DEMO.md` file.
* Provisions an environment for a "demo environment" to be deployed on top of.

> 📝 **NOTE**
>
> I recommend aliasing `ocp-aws-upi` for new OpenShift environments on AWS and `osa` for
> ROSA clusters if you need to create a base environment quickly.
>
> `ocp-aws-upi` is capable of deploying single-node clusters as well as using
> mixed instance types between control planes and worker nodes.

### GitOps Considerations

Demo environments provisioned by Demoland are maintained almost entirely by
GitOps. These components live in the `./bootstrap` directory within the demo
environment and provisioned with the `setup_gitops` function.

Anything that cannot be provisioned by GitOps is created by the `provision` or
`postinstall` scripts. Use this guidance to determine which script to use for
resources that can't be deployed by GitOps:

- Use `provision.sh` to add or configure hardware or anything with OpenShift on
  the clusters created by your base environment, like disks or NICs. Examples:
  - Creating `MachineConfig` CRs to configure CoreOS on the worker nodes.
  - Adding additional storage to worker nodes and formatting a filesystem onto
    them.
- Use `postinstall.sh` to add anything that's related to your demo environment
  specifically. Examples:
  - Creating `Secret`s or other CRs that will be used by applications/Kubernetes
    resources provisioned by GitOps
  - Waiting for an operator (that is managed by GitOps) to become ready.

## Quick Start

Here's how to deploy a demo environment, like the Red Hat Observability Demo
Environment, onto a base environment, like the `ocp-aws-sno` Single-node
OpenShift cluster demo environment, into your AWS account.

### Install prerequisites

```sh
brew install podman just sops gnupg
```

### Clone Demoland

```sh
git clone https://github.com/carlosonunez-redhat/demoland ./demoland
```

### Creating an encrypted config file

Create a GPG key to encrypt your Demoland config with, if you don't already have one...

```sh
gpg --quick-gen-key --batch --passphrase $PASSPHRASE $EMAIL_ADDRESS
```

- Replace `$EMAIL_ADDRESS` with your email address.
- Replace `$PASSPHRASE` with a strong password or '' if you don't want to use one.

...then save its fingerprint as a variable:

```sh
fingerprint=$(gpg --list-keys --with-colons $EMAIL_ADDRESS | grep -E '^fpr' | cut -f10 -d ':' | tail -1)
```

Create and encrypt a new config file from the already-encrypted example...

```sh
sed -E 's;ENC\[.*;replace-me;g' config.yaml |
    sops encrypt --pgp-fp "$fingerprint" --filename-override config.yaml > config.yaml
```

...then use sOps to safely modify it. Replace anything that says `replace-me`
with real values. (An index of configuration options is provided at the bottom
of this README.)

```sh
# Opens `vim`. Prepend the command below with EDITOR=code if you
# want to use VS Code.
sops config.yaml
```

<!-- vim-markdown-toc GFM -->

    * [Deploy the demo environment](#deploy-the-demo-environment)
    * [Use the demo environment](#use-the-demo-environment)
    * [Destroy the demo environment](#destroy-the-demo-environment)
* [Demolands](#demolands)
    * [Base Environments](#base-environments)
        * [`ocp-aws-upi`](#ocp-aws-upi)
    * [Demos](#demos)
        * [Local cluster observability with the Red Hat Observability Stack](#local-cluster-observability-with-the-red-hat-observability-stack)
        * [AI-Powered Multicluster Observability with Advanced Cluster Management and OpenShift Lightspeed](#ai-powered-multicluster-observability-with-advanced-cluster-management-and-openshift-lightspeed)
* [Components](#components)

<!-- vim-markdown-toc -->
### Deploy the demo environment

```sh
just deploy rhobs-demo
```

This will do the following in about 45 minutes:

- Use the `ocp-aws-sno` base infrastructure to create a single-node OpenShift cluster in AWS
- Configure your cluster with GitOps and install some default operators (Web
  Terminal, Dev Spaces)
- Add additional GitOps `Application`s that set up Red Hat Observability and its
  dependencies.


### Use the demo environment

Have fun!

### Destroy the demo environment

```sh
just destroy rhobs-demo
```

When you're done exploring/showing off the environment.


## Demolands

### Base Environments

#### `ocp-aws-upi`

|             |                                                                                                                     |
| :-----      | :-----                                                                                                              |
| **Code**    | [link](./environments/ocp-aws-upi)                                                                                  |
| **Purpose** | Deploys an OpenShift cluster on AWS with three worker nodes and three control plane nodes.                          |
| **Aliases** | **ocp-aws-sno**: Creates a single-node OpenShift cluster.                                                           |
|             | **ocp-aws-sno-metal**: Same as `ocp-aws-sno`, but deploys on a metal instance that's compatible with OpenShift Virt |

### Demos

#### Local cluster observability with the Red Hat Observability Stack

|             |                                                                                                                     |
| :-----      | :-----                                                                                                              |
| **README**  | [link](./environments/rhobs-demo/README.md)                                                                         |
| **Purpose** | Demonstrates how platform engineers can observe cluster and application behavior within and outside of OpenShift.   |

#### AI-Powered Multicluster Observability with Advanced Cluster Management and OpenShift Lightspeed

|             |                                                                                                                                     |
| :-----      | :-----                                                                                                                              |
| **README**  | [link](./environments/rhobs-multicluster-demo/README.md)                                                                            |
| **Purpose** | Demonstrates how platform engineers can observe cluster and application behavior across multiple OpenShift and Kubernetes clusters. |

## Components

These are addons rendered by
[Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
that you can install into Demoland Environments by either adding them to the
`components` section for your environment in `config.yaml` or with GitOps
through an ArgoCD `Application` or Flux `Kustomization`.

Go [here](./components/example) to view an example of a Demoland component.

| Name                                                                              | Description                                                                                                                  | Location                                                                                  |
| :----                                                                             | :-----                                                                                                                       | :---                                                                                      |
| `components/advanced-cluster-management/operators/acm`                            | Installs the ACM Operator.                                                                                                   | [link](./components/advanced-cluster-management/operators/acm)                            |
| `components/advanced-cluster-management/operators/multiclusterengine`             | Installs the Multicluster Engine (almost always installed with ACM).                                                         | [link](./components/advanced-cluster-management/operators/multiclusterengine)             |
| `components/advanced-cluster-management/resources/imported-cluster`               | Imports an OpenShift or Kubernetes cluster.                                                                                  | [link](./components/advanced-cluster-management/resources/imported-cluster)               |
| `components/advanced-cluster-management/resources/managed-cluster-set`            | Creates a ManagedClusterSet that, well, groups managed clusters into a set.                                                  | [link](./components/advanced-cluster-management/resources/managed-cluster-set)            |
| `components/advanced-cluster-management/resources/multicluster-observability/mco` | Deploys everything needed to make Multi-cluster Observability work (Thanos, Observatorium, Grafana, etc.)                    | [link](./components/advanced-cluster-management/resources/multicluster-observability/mco) |
| `components/advanced-cluster-management/resources/multiclusterengine`             | Deploys everything needed to enable multicluster management (Hive, mostly)                                                   | [link](./components/advanced-cluster-management/resources/multiclusterengine)             |
| `components/advanced-cluster-management/resources/multiclusterhub`                | Deploys everything needed to convert an OpenShift cluster into a multicluster hub (mostly Open Cluster Management)           | [link](./components/advanced-cluster-management/resources/multiclusterhub)                |
| `components/console-personalization/consolelinks/demoland`                        | Have you ever wanted to go straight to the Demoland source during a demo? Well, you can with this!                           | [link](./components/console-personalization/consolelinks/demoland)                        |
| `components/dev-spaces/resources/checluster`                                      | Deploys an Apache Che cluster used for Dev Spaces.                                                                           | [link](./components/dev-spaces/resources/checluster)                                      |
| `components/developer-hub/resources/backstage`                                    | Deploys a Red-Hat'ified version of Backstage as part of a Developer Hub deployment.                                          | [link](./components/developer-hub/resources/backstage)                                    |
| `components/example/resources/example`                                            | Demoland deploys this to confirm that component installs work.                                                               | [link](./components/example/resources/example)                                            |
| `components/openshift-gitops/resources/argocd-instance`                           | Deploys ArgoCD to enable GitOps.                                                                                             | [link](./components/openshift-gitops/resources/argocd-instance)                           |
| `components/openshift-lightspeed/resources/olsconfig/gcp_vertex_anthropic`        | Deploys an instance of OpenShift Lightspeed that's compatible with Anthropic Claude models via GCP Vertex.                   | [link](./components/openshift-lightspeed/resources/olsconfig/gcp_vertex_anthropic)        |
| `components/openshift-lightspeed/resources/olsconfig/gcp_vertex_gemini`           | Deploys an instance of OpenShift Lightspeed that's compatible with Google Gemini.                                            | [link](./components/openshift-lightspeed/resources/olsconfig/gcp_vertex_gemini)           |
| `components/openshift-logging/resources/clusterlogforwarders/combined`            | Creates an instance of cluster log forwarding (Loki and OTel)                                                                | [link](./components/openshift-logging/resources/clusterlogforwarders/combined)            |
| `components/openshift-logging/resources/clusterlogforwarders/lokistack`           | Creates an instance of cluster log forwarding (Loki only)                                                                    | [link](./components/openshift-logging/resources/clusterlogforwarders/lokistack)           |
| `components/openshift-logging/resources/clusterlogforwarders/opentelemetry`       | Creates an instance of cluster log forwarding (OTel only)                                                                    | [link](./components/openshift-logging/resources/clusterlogforwarders/opentelemetry)       |
| `components/openshift-logging/resources/loki-stack/secret/s3`                     | Template for creating the Loki S3 secret.                                                                                    | [link](./components/openshift-logging/resources/loki-stack/secret/s3)                     |
| `components/openshift-logging/resources/loki-stack/stack`                         | Deploys Loki for Cluster Log Forwarding.                                                                                     | [link](./components/openshift-logging/resources/loki-stack/stack)                         |
| `components/openshift-monitoring/resources/cluster-monitoring`                    | Enables Cluster Monitoring with Prometheus.                                                                                  | [link](./components/openshift-monitoring/resources/cluster-monitoring)                    |
| `components/openshift-observability/resources/observability-installer`            | Installs Cluster Observability components (Tempo, Loki, Console add-ons, etc)                                                | [link](./components/openshift-observability/resources/observability-installer)            |
| `components/openshift-observability/resources/ui-plugins/logging`                 | Enables the Logging Console UI Plugin                                                                                        | [link](./components/openshift-observability/resources/ui-plugins/logging)                 |
| `components/openshift-observability/resources/ui-plugins/monitoring`              | Enables the "Observe" Console UI Plugin                                                                                      | [link](./components/openshift-observability/resources/ui-plugins/monitoring)              |
| `components/openshift-observability/resources/ui-plugins/troubleshooting`         | Enables the "Signal Correlation" drop-down in the OpenShift Console                                                          | [link](./components/openshift-observability/resources/ui-plugins/troubleshooting)         |
| `components/openshift-otel/resources/instrumentation`                             | Enables OTel auto-instrumentation; learn more [here](https://opentelemetry.io/docs/platforms/kubernetes/operator/automatic/) | [link](./components/openshift-otel/resources/instrumentation)                             |
| `components/openshift-otel/resources/otelcollector`                               | Provisions an OpenTelemetry collector.                                                                                       | [link](./components/openshift-otel/resources/otelcollector)                               |
| `components/openshift-tracing/resources/tempo-stack/secret/s3`                    | Template for the Tempo S3 secret.                                                                                            | [link](./components/openshift-tracing/resources/tempo-stack/secret/s3)                    |
| `components/openshift-tracing/resources/tempo-stack/stack`                        | Provisions Tempo (tracing aggregator)                                                                                        | [link](./components/openshift-tracing/resources/tempo-stack/stack)                        |
| `components/rbac/cluster-role-binding/generic`                                    | Template for creating a cluster role binding.                                                                                | [link](./components/rbac/cluster-role-binding/generic)                                    |
| `components/rbac/cluster-role/generic`                                            | Template for creating a cluster role.                                                                                        | [link](./components/rbac/cluster-role/generic)                                            |
| `components/rbac/service-accounts/privileged`                                     | Template for creating a Service Account that can start privileged Pods.                                                      | [link](./components/rbac/service-accounts/privileged)                                     |
| `components/secret-templates/resources/grafana-secret/s3`                         | Template for the Grafana S3 secret.                                                                                          | [link](./components/secret-templates/resources/grafana-secret/s3)                         |
| `components/streams-for-apache-kafka/operators/amq-streams`                       | Provisions Strimzi for Kafka operator.                                                                                       | [link](./components/streams-for-apache-kafka/operators/amq-streams)                       |
| `components/streams-for-apache-kafka/operators/amq-streams-console`               | Provisions the Kafka Console operator.                                                                                       | [link](./components/streams-for-apache-kafka/operators/amq-streams-console)               |
| `components/streams-for-apache-kafka/resources/kafka-cluster`                     | Provisions Strimzi for Kafka.                                                                                                | [link](./components/streams-for-apache-kafka/resources/kafka-cluster)                     |
| `components/streams-for-apache-kafka/resources/kafka-console`                     | Provisions an instance of the Kafka Console.                                                                                 | [link](./components/streams-for-apache-kafka/resources/kafka-console)                     |
| `components/streams-for-apache-kafka/resources/kafka-topic`                       | Creates a Kafka topic within a AMQ Streams for Kafka instance.                                                               | [link](./components/streams-for-apache-kafka/resources/kafka-topic)                       |

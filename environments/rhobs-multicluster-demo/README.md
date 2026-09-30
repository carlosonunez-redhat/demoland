# Red Hat Multicluster Observability Demo

Understand platform-level behavior across all of your OpenShift clusters with
Advanced Cluster Management and Multicluster Observability.

<!-- vim-markdown-toc GFM -->

* [Three Key Points](#three-key-points)
* [Architecture](#architecture)
* [Setting Up](#setting-up)
    * [What You'll Need](#what-youll-need)
    * [Instructions](#instructions)
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

- An AWS Account with an Access and Secret Key Pair and enough permissions to
  create an OpenShift cluster and an EKS cluster.
- The AWS CLI
- An OpenShift Cluster with ACM installed (tested with OpenShift v4.20 and ACM
  v2.17)
- Access to a shell, like `bash`, `zsh` or `fish`

> 📝 **NOTE**
>
> You can also use [Carlos's Demoland](https://github.com/carlosonunez-redhat/demoland) to spin up
> everything you'll need to run this demo in about 90 minutes. (45 minutes for
> the ACM hub and 45 minutes for the two clusters it will manage.)

### Instructions

> 🚧 **Work In Progress**
>
> This environment is being built out. Further instructions will become
> available once that's complete.

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

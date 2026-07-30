# Hybrid Cloud Made Easy with ROSA

Quickly deploy your first hybrid cloud environment with self-managed OpenShift,
Red Hat OpenShift on AWS (ROSA) and OpenShift Service Mesh.

<!-- vim-markdown-toc GFM -->

* [Three Key Points](#three-key-points)
* [Architecture](#architecture)
* [Setting Up](#setting-up)
    * [What You'll Need](#what-youll-need)
    * [Instructions](#instructions)
* [Demo](#demo)
    * [Consistent Platform Experience On Any Cloud](#consistent-platform-experience-on-any-cloud)
    * [Deploy Applications On-Prem or Into The Cloud with GitOps](#deploy-applications-on-prem-or-into-the-cloud-with-gitops)
    * [Build Applications That Speak Hybrid Cloud from Day One](#build-applications-that-speak-hybrid-cloud-from-day-one)
    * [Burst On-Premise Applications Into the Cloud](#burst-on-premise-applications-into-the-cloud)
    * [Next Steps](#next-steps)

<!-- vim-markdown-toc -->
    * [Deploy Applications On-Prem or Into The Cloud with GitOps](#deploy-applications-on-prem-or-into-the-cloud-with-gitops)
    * [Build Applications That Speak Hybrid Cloud from Day One](#build-applications-that-speak-hybrid-cloud-from-day-one)
    * [Burst On-Premise Applications Into the Cloud](#burst-on-premise-applications-into-the-cloud)
    * [Next Steps](#next-steps)

<!-- vim-markdown-toc -->
## Three Key Points

- Deploy and manage a hybrid cloud application platform with minimal operational
  overhead with **OpenShift Self-Managed** and **Red Hat OpenShift on AWS
  (ROSA)**
- Seamlessly deploy and migrate cloud-native applications on-prem and into AWS
  with **OpenShift Service Mesh**.
- Burst on-premise applications into the cloud with ease with **OpenShift
  Service Mesh** and **Kubernetes Event-Driven Autoscaling**

## Architecture

![](./include/assets/img/architecture.png)

WIP.


## Setting Up

### What You'll Need

- An AWS Account with an Access and Secret Key Pair
- The AWS CLI
- An OpenShift Cluster (tested with v4.22)
- Access to a shell, like `bash`, `zsh` or `fish`

> 📝 **NOTE**
>
> You have several options if you don't have an OpenShift cluster handy:
>
> - [OpenShift Local](https://developers.redhat.com/products/openshift-local) or
> - Stand up a Single-Node OpenShift cluster in about 45 minutes
>   with [Carlos's Demoland](https://github.com/carlosonunez-redhat/demoland).

### Instructions

WIP

## Demo

Your company has several large applications running on-premise. While
applications written within the last few years have been running in the cloud,
deciding where workloads will go is very much an either-or decision.
Specifically, if you want access to long-standing internal systems or systems
that will remain on-premise for some time, such as mainframe application
frontends or critical databases, your application will likely need to live
on-premise.

The complexity of deploying and managing applications within both IaaS tiers is
substantial. Managed services in the cloud are nice and save a lot of time, but
maintaining these along with their on-premise compliments is operationally
taxing and is a large source of toil and headache.

Ideally, your company would like to have a single, consistent hybrid-cloud platform that runs
anywhere and is smart enough to speak on-premise _and_ managed cloud services.
This way, your company can reap two significant benefits: (a) a single set of
governance, security and architecture models that apply to applications
regardless of the IaaS they reside on, and (b) reduced vendor lock-in and financial
leverage to operate wherever makes the most financial sense.

Let's walk through how OpenShift is able to be that hybrid cloud platform.

<!-- vim-markdown-toc GFM -->

* [Consistent Platform Experience On Any Cloud](#consistent-platform-experience-on-any-cloud)
* [Deploy Applications On-Prem or Into The Cloud with GitOps](#deploy-applications-on-prem-or-into-the-cloud-with-gitops)
* [Build Applications That Speak Hybrid Cloud from Day One](#build-applications-that-speak-hybrid-cloud-from-day-one)
* [Burst On-Premise Applications Into the Cloud](#burst-on-premise-applications-into-the-cloud)

### Consistent Platform Experience On Any Cloud

_WIP_

### Deploy Applications On-Prem or Into The Cloud with GitOps

_WIP_

### Build Applications That Speak Hybrid Cloud from Day One

_WIP_

### Burst On-Premise Applications Into the Cloud

_WIP_

### Next Steps

_WIP_

# vSphere to Virt for Application Development

This demo outlines how to cut across silos and accelerate application
development by migrating VMs and their vRA/Aria Automation/VCF-A workflows to Ansible and
OpenShift Virt and making self-service requests for developers easy with
Developer Hub.

## Three Key Points

- Use the **Migration Toolkit for Virtualization** to migrate virtual machines
  into OpenShift Virt from vSphere.
- Use **OpenShift AI** and **Ansible Lightspeed** to convert vRA/Aria
  Automation/VCF-A workflows and blueprints into Ansible playbooks with
  self-hosted models
- Use **Red Hat Developer Hub** to create applications and instances of
  virtualized components conformant with enterprise best practices and security
  guidelines.

## Architecture

![](./include/assets/img/architecture.png)

This demo can be broken up into three phases:

- Current vSphere environment
- Migration from vSphere to OpenShift Virt
- Up and running in OpenShift

### Current vSphere Environment

In the vSphere environment, VMs are created with a two-step process:

1. Execute a Aria Workflow through the Aria Ops Catalog that creates a VM from
   an existing clone, and
2. Make the VM available to the developer.

### Migrating from vSphere to OpenShift Virt

Being able to move existing VMs and replicate existing automation with minimal
effort is important. This is accomplished by this demo by doing the following:

3. Use the **Migration Toolkit for VMware** to quickly migrate VMs in vSphere into
   OpenShift Virt.
4. Use **Ansible Lightspeed** and **OpenShift AI** to analyze workflows in Aria
   Automation, convert them into Ansible playbooks and publish them into
   **Ansible Automation Platform**.

### Up and Running in OpenShift

Providing a self-service portal for developers to request VMs alongside their
containerized applications is possible with OpenShift Virt. Here is how that's
done:

5. Use **Developer Hub** to host catalog entries that execute the playbooks
   created above through templates.
6. Developers request VMs for their applications through **Developer Hub**.
   Ansible creates and publishes the VMs.

## Setting Up

### What You'll Need

- An AWS Account with an Access and Secret Key Pair
- The AWS CLI
- An OpenShift Cluster (tested with v4.20)
- Access to a shell, like `bash`, `zsh` or `fish`

> 📝 **NOTE**
>
> You have several options if you don't have an OpenShift cluster handy:
>
> - [OpenShift Local](https://developers.redhat.com/products/openshift-local) or
> - Stand up a Single-Node OpenShift cluster in about 45 minutes
>   with [Carlos's Demoland](https://github.com/carlosonunez-redhat/demoland).

### Instructions

## Demo

### Scenario

You are a vSphere administrator that is, amongst other things, responsible for
the VM templates that deploy your organization's database.

This VM template is mature and highly optimized for your organization's needs.
Containerizing it is on the table but requires finesse and will take time.

The business has decided to move away from Broadcom, and fast. You need to move
this database but are interested in knowing how developers can create instances
of it alongside their containerized applciations.

### Migrate VM into OpenShift with the Migration Toolkit for VMs

### Convert VM Template Creation vRA Workflow to Ansible with AI Agents

### Create Self-Service Offering in Developer Hub

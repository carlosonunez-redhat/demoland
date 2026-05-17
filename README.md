# Demoland

![](./assets/img/demoland.png)

Create end-to-end OpenShift demos on fresh OpenShift clusters that you own.

## Why

### TLDR

Originally a project to learn OpenShift; grew into a landing zone for
custom customer-facing demos slated for publication into other Red Hat mediums.

### Longform

At first, I created this to learn the nooks and crannies of OpenShift by doing
it "the hard way" on AWS with our [user-provisioned install
(UPI)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_on_aws/user-provisioned-infrastructure#upi-aws-installation-reqs)
method.

Upon becoming a Specialist SA at Red Hat, I frequently found myself in
situations where I needed to whip up a custom product demo on an OpenShift
cluster quickly. While Red Hat has [an excellent demo platform (Red Hat SSO
credentials required)](https://catalog.demo.redhat.com), custom environments
fare better for demonstrating specific use cases or showing one-offs during an
on-site workshop.

Demoland has been a great place to centralize and document these demos as well
as serve as a starting point for publishing onto Red Hat blogs or into RHDP or
the Red Hat Arcade at https://interact.redhat.com.

## How it works

Demolands are comprised of **base infrastructure** and **demo environments**.

### Demo Environments

**Demo environments** are the scripts and Kustomizations (applied via GitOps)
that aim to demonstrate product capabilities.

<b><u>Criteria</u></b>

* Has a `DEMO.md` file that outlines the "resounding message" of the demo,
  "three key points" that the demo will walk through, and the demo "run of
  show".
* Does _not_ deploy foundational products, like OpenShift or AAP.
* Can live outside of Demoland, i.e. scripts, Kustomizations and other
  automation aside from Demoland entrypoints (explained below) do not require
  Demoland scaffolding to be deployed.

### Base Infrastructure

**Base infrastructure** is the infrastructure on which demo environments are
served, like OpenShift and AAP.

<b><u>Criteria</u></b>

* Does NOT have a `DEMO.md` file.
* Provisions an environment for a "demo environment" to be deployed on top of.

### Directory Structure

```
├── apps
│   ├── app-1
│   └── app-2
│   └── ...
│   └── app-n
├── components
│   ├── component-1
│   ├── component-2
│   ├── ...
│   ├── component-n
├── environments
│   ├── example
│   │   ├── gitops
│   │   ├── include
│       │   ├── helper_1.sh
│       │   ├── helper_2.sh
│       │   ├── ...
│       │   ├── helper_n.sh
│   │   ├── preflight.sh
│   │   ├── provision.sh
│   │   ├── expose.sh
│   │   ├── postinstall.sh
│   │   ├── destroy.sh
├── include
│   ├── containerfiles
│   ├── helpers
│   └── templates
├── config.yaml
├── Justfile
└── README.md
```

| **File/Directory**                   | **Purpose**                                                   | **Used for Base Infra?** | **Used for Demo Envs?**         |
| :---                                 | :---                                                          | :---                     | :---                            |
| `./config.yaml`                      | Config for base infra and demo envs. Encrypted with sOps.     | Yes                      | Yes                             |
| `./Justfile`                         | Demoland commands, like `deploy` and `postinstall`.           | Yes                      | Yes (Demoland entrypoints only) |
| `./include`                          | Helper libraries usable by all demo envs/base infra           | Yes                      | Yes (Demoland entrypoints only) |
| `./environments/$ENV/preflight.sh`   | Demoland entrypoint for executing preflight checks            | Yes                      | Yes                             |
| `./environments/$ENV/provision.sh`   | Provisions base infra or a demo env.                          | Yes                      | No                              |
| `./environments/$ENV/expose.sh`      | Exposes files/secrets to "dependent" base infra or demo envs. | Yes                      | No                              |
| `./environments/$ENV/postinstall.sh` | Executes post-installation steps, like setting up GitOps.     | Yes                      | Yes                             |
| `./environments/$ENV/destroy.sh`     | Tears downs a demo env and its base infra.                    | Yes                      | Yes                             |
| `./environments/$ENV/include/`       | Base infra or demo env-scoped helper libraries.               | Optional                 | Optional                        |
| `./environments/$ENV/gitops/`        | Kustomizations to apply via OpenShift GitOps/ArgoCD.          | Optional                 | Optional                        |
| `./components`                       | Reusable resources to apply/customize via GitOps.             | Optional                 | Yes                             |
| `./apps`                             | Example applications used within demos.                       | No                       | Yes                             |

## Quick Start

Here's how to deploy the Red Hat Observability Demo Environment onto a
Single-node OpenShift cluster in your AWS account.

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


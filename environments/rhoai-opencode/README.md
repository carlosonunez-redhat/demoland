Agentic App Dev with OpenShift AI 3, OpenShift Dev Spaces and Opencode
========================================================================

## Resounding Message

Offer developers modern agents with your guardrails through OpenShift AI 3 and
OpenShift Dev Spaces.

## Three Key Points

- Use **Dev Spaces** to offer developers an environment to build in that's
  faster than a VDI but just as bound to your corporate standards.

- Use **OpenShift AI** to serve private, open-source models that are fine-tuned
  on your data

- Provide developers with a modern and open-source agentic app dev experience
  with **OpenCode**.

## Deploying the Demo

### Prerequisites

- An AWS account with access to GPU-enabled instances
- An IAM user with an `AdministratorAcccess` policy (or the ability to assume
  a role with this policy)

`just deploy rhoai-opencode`

This will:

- Deploy OpenShift 4.20
- Install the OpenShift AI and OpenShift Dev Spaces operators
- Serve Mistral Devstral 2 from OpenShift AI vLLM
- Create a Dev Spaces workspace from [this
  codebase](https://github.com/carlosonunez-redhat/opencode-devspace)

## Using the Demo

_Work in progress_

## To-Dos

- [ ] Add Developer Hub golden path with default rules and skills
- [ ] Add MCP-backed skills

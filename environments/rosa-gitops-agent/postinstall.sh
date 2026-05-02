#!/usr/bin/env bash
# Exposes data and secrets between environments during a deployment run.
#
# This adds some functions for working with cloud providers, the config file, and
# other useful things.
source "$INCLUDE_DIR/helpers/aws.sh"
source "$INCLUDE_DIR/helpers/config.sh"
source "$INCLUDE_DIR/helpers/data.sh"
source "$INCLUDE_DIR/helpers/errors.sh"
source "$INCLUDE_DIR/helpers/gitops.sh"
source "$INCLUDE_DIR/helpers/logging.sh"
source "$INCLUDE_DIR/helpers/install_config.sh"
source "$INCLUDE_DIR/helpers/yaml.sh"

# If this environment has includes of its own, use the $ENVIRONMENT_INCLUDE_DIR environment
# variable, like shown in the comment below.
#
# source "$ENVIRONMENT_INCLUDE_DIR/foo.sh"
source "$ENVIRONMENT_INCLUDE_DIR/rosa.sh"

_cluster_name() {
  oc get infrastructure cluster -o yaml |
    yq -r '.status.platformStatus.aws.resourceTags[] | select(.key == "api.openshift.com/name") | .value'
}

create_irsa_for_cluster_api() {
  _iam_irsa_role_exists() {
    _exec_aws iam list --query 'Roles[*].RoleName' --output text |
      grep -q "capa-manager-role-$(_cluster_name)"
  }

  _create_iam_irsa_role() {
    oidc_provider=$(oc get authentication.config.openshift.io cluster -o json |
      jq -r .spec.serviceAccountIssuer |
      sed 's/https:\/\///')
    oidc_provider_arn=$(_exec_aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[*].Arn' --output text |
      grep "$oidc_provider")
  }

  _iam_irsa_role_exists && return 0

  info "Creating IRSA role for Cluster API"
  _create_iam_irsa_role
}

setup_gitops rosa-gitops-agent bootstrap/operators environment-operators
setup_gitops rosa-gitops-agent bootstrap/resources environment-resources
create_irsa_for_cluster_api hcp

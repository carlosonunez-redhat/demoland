#!/usr/bin/env bash
# Provisions an environment!
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
source "$ENVIRONMENT_INCLUDE_DIR/rhobs.sh"

create_rhobs_s3_bucket() {
  _exec_aws s3 ls | grep -q "$(rhobs_s3_bucket)" && return 0

  info "Creating RHOBS S3 bucket: $(rhobs_s3_bucket)"
  _exec_aws s3 mb "s3://$(rhobs_s3_bucket)"
}

replace_bucket_vars_in_kustomizations() {
  local replacements_made
  replacements_made=0
  while read -r file
  do
    replacements_made=$((replacements_made+1))
    sed "s/\$REPLACE_BUCKET\$/$(rhobs_s3_bucket)/g ; s/\$REPLACE_REGION\$/$(_exec_aws configure get region)/g" "$file"
  done < <(grep -lr "\$REPLACE_" ./bootstrap)
  echo "$replacements_made"
}

set -e
create_rhobs_s3_bucket
replacements=$(replace_bucket_vars_in_kustomizations)
if test "$replacements" -gt 0
then
  info "Variables in GitOps kustomizations replaced. Commit first then perform post-install again."
  return 0
fi
setup_gitops rhobs-demo bootstrap/operators bootstrap-rhobs-demo-operators
setup_gitops rhobs-demo bootstrap/resources/rhobs rh-observability

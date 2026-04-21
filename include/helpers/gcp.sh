# shellcheck shell=bash
source "$(dirname "$0")/../include/helpers/cloud_creds.sh"

_gcloud_activate_sa() {
  test -f /tmp/.gcloud_activated && return 0

  sa=$(_get_cloud_cred gcp service_account | yq -o=j -I=0 '.')
  test -z "$sa" && return 1
  project_id=$(_get_cloud_cred gcp project_id)
  test -z "$project_id" || project_id=$(jq -r '.project_id' <<< "$sa")
  echo "$sa" | gcloud auth activate-service-account --key-file - --project="$project_id" &&
    touch /tmp/.gcloud_activated
}

_exec_gcloud() {
  if ! _gcloud_activate_sa
  then
    error "gcloud failed to activate the service account in config"
    return 1
  fi
  gcloud "$@"
}

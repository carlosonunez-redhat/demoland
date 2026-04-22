set shell := [ "bash", "-uc" ]
set unstable := true
set quiet := true

container_bin := env("CONTAINER_BIN", which('podman'))
container_image := 'demo-environment-runner'
oc_container_image := 'openshift-client'
container_vol := 'demo-environment-runner-vol'
container_secrets_vol := 'demo-environment-runner-secrets-vol'
container_environment_info_vol := 'demo-environment-runner-env-info-vol'
container_postinstall_vol := 'demo-environment-postinstall-vol'
config_file := source_dir() + '/config.yaml'
yq_image := 'mikefarah/yq'
default_openshift_version := "4.19.27"

[doc("Cleans temporary files and such unless another just operation is happening.")]
clean:
  just_processes=$(ps -ef | grep just | grep -v grep | wc -l); \
  test "$just_processes" -gt 1 && exit 0; \
  just _log info "Cleaning up temp files."; \
  rm -rf /tmp/*demoland_temp*;


[doc("Creates a new environment")]
create_new_environment environment:
  env=$(just _environment_name '{{ environment }}'); \
  if just _confirm_environment "$env"; \
  then \
    just _log info "Environment already exist: '$env'. Nothing to do."; \
    exit 0; \
  fi; \
  just _log info "Creating new environment: '$env'"; \
  just _create_new_env_dir_structure "$env" && just _add_env_to_config "$env";

[doc("Deletes an environment (CAREFUL!!!!)")]
delete_environment environment: (_confirm_environment environment)
  delete_magic='confirm delete - {{ environment }}'; \
  read -p "Type '$delete_magic' to continue deleting this environment: " input; \
  if test "$delete_magic" != "$input"; \
  then \
    just _log info "Deletion cancelled."; \
    exit 0; \
  fi; \
  just _delete_env_dir '{{ environment }}' && just _delete_env_from_config '{{ environment }}';

[doc("Lists environments.")]
list_environments:
  sops decrypt {{ config_file }} | yq -r '.environments | to_entries | .[].key' | grep -v example

[doc("Checks an environment before a deployment.")]
precheck environment: \
  (_run_stage_with_dependencies environment "_precheck")

[doc("Deploys an environment")]
deploy environment: clean \
    (_run_stage_with_dependencies environment "_precheck" "_provision" "_expose" "_postinstall")

[doc("Destroys an environment")]
destroy environment: clean \
    (_run_stage_with_dependencies environment "_destroy")

[doc("Performs post-install steps, like installing operators and such.")]
postinstall environment: (_run_stage_with_dependencies environment "_postinstall")

_run_stage_with_dependencies environment +stages:\
    (_generate_toplevel_environment_info environment) \
    (_generate_container_vol environment ) \
    (_generate_container_secrets_vol environment )
  set +u; \
  envs="{{ environment }}"; \
  if test -z "$SKIP_DEPENDENCIES"; \
  then \
    if echo '{{ stages }}' | grep -q destroy; \
    then envs="{{ environment }};$(just _get_dependent_environments {{ environment }})"; \
    else envs="$(just _get_dependent_environments {{ environment }});{{ environment }}"; \
    fi; \
  fi; \
  set -eu; \
  for env in $(echo "$envs" | sed -E 's/^;//' | tr ';' '\n'); \
  do just _confirm_environment "$env" || exit 1; \
  done; \
  for env in $(echo "$envs" | sed -E 's/^;//' | tr ';' '\n'); \
  do \
    for stage in {{ stages }}; \
    do \
      stage_friendly_name=$(sed -E 's/^_//' <<< "$stage"); \
      env_details="environment [$env]"; \
      test "$env" != '{{ environment }}' && env_details="dependent environment [$env]"; \
      resolved_env=$(just _resolved_environment_name "$env"); \
      test "$env" != "$resolved_env" && env_details="$env_details (alias of: $resolved_env)"; \
      just _log info "Running operation [$stage_friendly_name] on $env_details"; \
      just "$stage" "$env"; \
    done; \
  done;

_precheck environment:
  set +u; \
  if test -n "$SKIP_PRECHECK"; \
  then \
    just _log info "Preflight checks skipped for environment '{{ environment }}'"; \
    exit 0; \
  fi; \
  set -u; \
  just _execute_containerized '{{ environment }}' \
    'preflight.sh' \
    'true' \
    'Environment {{ environment }} does not have preflight checks; skipping.';

_provision environment: (_ensure_toplevel_environment_info_available environment)
  just _execute_containerized '{{ environment }}' 'provision.sh';

_expose environment: (_ensure_toplevel_environment_info_available environment)
  just _execute_containerized '{{ environment }}' \
    'expose.sh' \
    'true' \
    'Environment {{ environment }} does not have anything to expose; skipping.';

_postinstall environment: (_ensure_toplevel_environment_info_available environment) \
  (_ensure_toplevel_environment_has_kubeconfig environment) \
  (_ensure_container_postinstall_volume_exists environment) \
  (_ensure_openshift_client_image environment ) \
  (_clear_postinstall_volume environment) \
  (_install_components_into_environment environment)

_install_components_into_environment environment:
  just _get_environment_components '{{ environment }}' | \
    while read -r component; \
    do \
      for stage in _ensure_component_exists _stage_component _create_component_kustomization _install_component; \
      do just "$stage" '{{ environment }}' "$component" || exit 1; \
      done; \
    done

_stage_component environment component:
  {{ container_bin }} run --rm \
      -v "$(just _container_postinstall_vol '{{ environment }}'):/vol" \
      -v "$PWD/components:/components" \
      bash:5 -c "mkdir -p /vol/base && cp -r /components/{{ component }}/* /vol/base/"

_get_environment_components environment:
  env_data=$(just _merge_aliased_environment "{{ environment }}") || exit 1; \
  just _run_yq "$env_data" '.components[]'

_create_component_kustomization environment component:
  k="$(echo -en 'resources:\n- ./base')"; \
  for overlay_f in $(just _component_overlays '{{ environment }}' '{{ component }}'); \
  do \
    fname=$(basename "$overlay_f"); \
    just _log info "[postinstall] Adding overlay to component '{{ component }}': $overlay_f"; \
    overlay=$(grep -Eiv '^apiversion:' "$overlay_f" | grep -Eiv '^kind:'); \
    k=$(echo -e "${k}\n${overlay}"); \
  done; \
  k_enc=$(base64 -w 0 <<< "$k"); \
  {{ container_bin }} run --rm -v "$(just _container_postinstall_vol '{{ environment }}'):/vol" \
      bash:5 -c "echo '$k_enc' | base64 -d > /vol/kustomization.yaml"

_install_component environment component:
  env=$(just _resolved_environment_name '{{ environment }}'); \
  just _log info "[postinstall] Installing component '{{ component }}' in environment '$env'"; \
  {{ container_bin }} run --rm \
    -v "$(just _container_postinstall_vol '{{ environment }}'):/vol" \
    -v "$(just _container_secrets_vol_shared):/shared/secrets" \
    {{ oc_container_image }} \
    --kubeconfig $(just _toplevel_environment_kubeconfig '{{ environment }}') apply -k /vol


_ensure_openshift_client_image environment:
  set +u; \
  test -z "$REBUILD_OPENSHIFT_CLIENT_IMAGE" && \
    {{ container_bin }} image ls | grep -q "{{ oc_container_image }}" && exit 0; \
  set -u; \
  openshift_version=$(just _get_property_from_env_config_use_alias \
    {{ environment }} \
    '.deploy.cluster_config.openshift_version'); \
  test -z "$openshift_version" && openshift_version={{ default_openshift_version }}; \
  just _log info "(re)building OpenShift client image [openshift version: $openshift_version]"; \
  {{ container_bin }} image build -t "{{ oc_container_image }}" \
    --build-arg OPENSHIFT_VERSION="$openshift_version" - < "$PWD/include/containerfiles/client.Dockerfile"

_ensure_component_exists environment component:
  test -d "$PWD/components/{{ component }}" && exit 0; \
  just _log error "Environment '{{ environment }}' wants component '{{ component }}', which doesn't exist"; \
  exit 1;

_ensure_container_postinstall_volume_exists environment:
  set +u; \
  vol=$(just _container_postinstall_vol {{ environment }}); \
  {{ container_bin }} volume ls | grep -q "$vol" && \
    test -z "$REBUILD_POSTINSTALL_VOLUME" && \
    exit 0; \
  test -n "$REBUILD_POSTINSTALL_VOLUME" && {{ container_bin }} volume rm -f "$vol" >/dev/null; \
  {{ container_bin }} volume create "$vol" >/dev/null; \

_clear_postinstall_volume environment:
  {{ container_bin }} run --rm -v "$(just _container_postinstall_vol '{{ environment }}'):/vol" \
      bash:5 -c "rm -rf /vol/*"

_component_overlays environment component:
  overlays_dir="$(just _get_environment_directory '{{ environment }}')/overlays/{{ component }}"; \
  test -d "$overlays_dir" || exit 0; \
  find "$overlays_dir" -type f;

_destroy environment:
  just _execute_containerized '{{ environment }}' 'destroy.sh';

_get_dependent_environments environment:
  set +u; \
  env_data=$(sops --decrypt --extract '["environments"]["{{ environment }}"]' \
    --output-type yaml "{{ config_file }}" | grep -Ev '^[ ]{0,}#') || exit 1; \
  dependencies=$(just _run_yq "$env_data" '.depends_on'); \
  if test -z "$dependencies" || test "$dependencies" == null; \
  then exit 0; \
  fi; \
  just _run_yq "$env_data" '.depends_on | join(";")' | grep -Ev '^null$'; \

_environment_name environment:
  echo '{{ environment }}' | tr ' ' '_'

_resolved_environment_name environment: (_confirm_environment_in_config environment)
  set +u; \
  env_data=$(sops --decrypt --extract '["environments"]["{{ environment }}"]' \
    --output-type yaml "{{ config_file }}" | grep -Ev '^[ ]{0,}#') || exit 1; \
  alias=$(just _run_yq "$env_data" '.alias_of'); \
  if test -z "$alias" || test "$alias" == 'null'; \
  then echo '{{ environment }}' && exit 0; \
  fi; \
  echo "$alias";

_create_new_env_dir_structure environment:
  cp -r "$(just _get_environment_directory_no_alias 'example')" \
    "$(just _get_environment_directory_no_alias '{{ environment }}')"

_delete_env_dir environment:
  rm -r "$(just _get_environment_directory '{{ environment }}')"

_add_env_to_config environment:
  conf=$(sops --decrypt --extract '["environments"]["example"]' \
    --output-type json {{ config_file }} | grep -Ev '^[ ]{0,}#'); \
  sops set {{ config_file }} '["environments"]["{{ environment }}"]' "$conf"

_delete_env_from_config environment:
  sops unset {{ config_file }} '["environments"]["{{ environment }}"]'

_print_container_vol_name_for_environment environment vol_name:
  set +u; \
  sentinel_f=$(just _sentinel_file '{{ vol_name }}'); \
  if test -f "$sentinel_f" ; \
  then \
    cat "$sentinel_f"; \
    exit 0; \
  fi; \
  set -u; \
  env=$(echo "{{ environment }}" | \
        base64 -w 0 | \
        tr -d '=' | \
        head -c 8); \
  echo "{{ vol_name }}-$env" | tee "$sentinel_f"

_container_vol environment: \
  ( _print_container_vol_name_for_environment environment container_vol)

_container_secrets_vol environment: \
  ( _print_container_vol_name_for_environment environment container_secrets_vol)

_container_postinstall_vol environment: \
  ( _print_container_vol_name_for_environment environment container_postinstall_vol)

_container_environment_info_vol environment: \
  ( _print_container_vol_name_for_environment environment container_environment_info_vol)

_container_vol_shared:
  echo "{{ container_vol }}-shared"

_container_secrets_vol_shared:
  echo "{{ container_secrets_vol }}-shared-secrets"

_container_image environment:
  env=$(just _resolved_environment_name '{{ environment }}'); \
  echo "{{ container_image }}-$env"

_execute_containerized environment file ignore_not_found='false' custom_message='none': \
    ( _ensure_container_image_exists environment ) \
    ( _ensure_container_secrets_vol_populated environment )
  file=$(just _get_environment_directory_file {{ environment }} {{ file }}); \
  if ! test -f "$file"; \
  then \
    level=error; \
    message="File not found in environment: {{ file }}"; \
    test "{{ custom_message }}" != 'none' && message="{{ custom_message }}"; \
    if test "{{ ignore_not_found }}" != 'false'; \
    then \
      level=warning; \
      message="${message} (skipping)"; \
    fi; \
    just _log "$level" "$message"; \
    test "{{ ignore_not_found }}" == 'false' && exit 1; \
  fi; \
  file_lines=$(grep -Ev '^#|source.*\.sh$' "$file" | grep -Ev '^$' | wc -l); \
  if test "$file_lines" -eq 0; \
  then \
    just _log info "'$file' is empty. Go put some stuff into it!"; \
    exit 0; \
  fi; \
  command=({{ container_bin }} run --rm -it \
    -v "$(just _container_vol {{ environment }}):/data" \
    -v "$(just _container_environment_info_vol {{ environment }}):/environment_info" \
    -v "$(just _container_secrets_vol {{ environment }}):/secrets" \
    -v "$(just _container_vol_shared):/shared/data" \
    -v "$(just _container_secrets_vol_shared):/shared/secrets" \
    -v $PWD/include:/app/include \
    -v "$(just _get_environment_directory {{ environment }}):/app/environment" \
    -e INCLUDE_DIR=/app/include \
    -e ENVIRONMENT_INCLUDE_DIR=/app/environment/include \
    -w /app); \
  while read var; \
  do command+=(-e "$var"); \
  done < <(just _run_yq \
    "$(just _get_property_from_env_config {{ environment }} '.deploy.environment_vars')" \
    '.[]'); \
  command+=($(just _container_image {{ environment }}) /app/environment/{{ file }}); \
  set +u; \
  test -n "$SHOW_CONTAINER_COMMANDS" && just _log info "Running containerized command: ${command[@]}"; \
  set -u; \
  "${command[@]}"

_merge_aliased_environment environment:
  set +u; \
  env_data=$(sops --decrypt --extract '["environments"]["{{ environment }}"]' \
    --output-type yaml "{{ config_file }}" | grep -Ev '^[ ]{0,}#') || exit 1; \
  env_data_enc=$(base64 -w 0 <<< $env_data); \
  alias=$(just _run_yq "$env_data" '.alias_of'); \
  if test -z "$alias" || test "$alias" == 'null'; \
  then echo "$env_data" && exit 0; \
  fi; \
  q=$(printf '["environments"]["%s"]' "$alias"); \
  target_env_data=$(sops --decrypt --extract "$q" --output-type yaml "{{ config_file }}") || exit 1; \
  target_env_data_enc=$(base64 -w 0 <<< $target_env_data); \
  just _do_yq_encoded_merge "$target_env_data_enc" "$env_data_enc"

_merge_cloud_creds environment:
  set +u; \
  cloud_data=$(sops --decrypt --extract '["common"]["cloud_credentials"]' \
    --output-type yaml "{{ config_file }}"); \
  if test -z "$cloud_data" || test "$cloud_data" == "null"; \
  then \
    just _log info "This config doesn't have any cloud config data. Skipping cloud config generation."; \
    exit 0; \
  fi; \
  cloud_data_enc=$(base64 -w 0 <<< $cloud_data); \
  env_data=$(just _merge_aliased_environment "{{ environment }}") || exit 1; \
  env_cloud_data=$(just _run_yq "$env_data" '.cloud_credentials'); \
  if test -z "$env_cloud_data" || test "$env_cloud_data" == null; \
  then \
    echo "$cloud_data"; \
    exit 0; \
  fi; \
  env_cloud_data_enc=$(base64 -w 0 <<< $env_cloud_data); \
  just _do_yq_encoded_merge "$cloud_data_enc" "$env_cloud_data_enc"

# the environment info volume stores information about the environment that executed
# a deploy/destroy run that can be consumed by dependencies of an environment (kind of like
# the Downward API in Kubernetes).
_toplevel_environment environment:
    {{ container_bin }} run --rm \
      -v "$(just _container_environment_info_vol {{ environment }}):/info" \
      bash:5 -c "test -f /info/root_environment_name && cat /info/root_environment_name"; \

_generate_toplevel_environment_info environment:
  set +u; \
  vol=$(just _container_environment_info_vol {{ environment }}); \
  {{ container_bin }} volume ls | grep -q "$vol" || \
    {{ container_bin }} volume create "$vol" >/dev/null; \
  for kvp in "root_environment_name:{{ environment }}" \
      "root_environment_id:$(base64 -w 0 <<< '{{ environment }}' | tr -d '=')"; \
  do \
    k=$(cut -f1 -d ':' <<< "$kvp"); \
    v=$(sed -E "s/^${k}://" <<< "$kvp"); \
    {{ container_bin }} run --rm \
      -v "${vol}:/info" \
      bash:5 -c "echo '$v' > /info/$k"; \
  done; \

_ensure_toplevel_environment_info_available environment:
  vol=$(just _container_environment_info_vol {{ environment }}); \
  {{ container_bin }} volume ls | grep -q "$vol" && \
    {{ container_bin }} run --rm \
      -v "${vol}:/info" \
      bash:5 -c 'test -n "$(cat /info/root_environment_name)"' && \
      exit 0; \
  just _log error "Toplevel environment info hasn't been created yet"; \
  exit 1

_ensure_toplevel_environment_has_kubeconfig environment:
  test -n "$(just _toplevel_environment_kubeconfig '{{ environment }}')" && exit 0; \
  just _log error "A kubeconfig isn't available yet for environment '$(just _toplevel_environment '{{ environment }}')'"; \
  exit 1

_generate_container_secrets_vol environment:
  set +u; \
  vol=$(just _container_secrets_vol {{ environment }}); \
  if test -n "$REBUILD_SECRETS_VOLUME" || \
    test -n "$({{ container_bin }} volume ls | grep -q "$vol")"; \
  then \
    test -n "$REBUILD_SECRETS_VOLUME" && {{ container_bin }} volume rm -f "$vol" >/dev/null; \
    {{ container_bin }} volume create "$vol" >/dev/null; \
  fi;

_ensure_container_secrets_vol_populated environment:
  set +u; \
  vol=$(just _container_secrets_vol {{ environment }}); \
  env_data=$(just _merge_aliased_environment '{{ environment }}'); \
  cloud_creds_data=$(just _merge_cloud_creds '{{ environment }}'); \
  env_data_enc=$(base64 -w 0 <<< "$env_data"); \
  cloud_creds_data_enc=$(base64 -w 0 <<< "$cloud_creds_data"); \
  {{ container_bin }} run --rm \
    -v "$vol:/secrets" \
    -v "$(just _container_environment_info_vol {{ environment }}):/environment_info" \
    bash:5 -c "echo '$env_data_enc' | base64 -d > /secrets/config-\$(cat /environment_info/root_environment_id).yaml" && \
  {{ container_bin }} run --rm \
    -v "$vol:/secrets" \
    -v "$(just _container_environment_info_vol {{ environment }}):/environment_info" \
    bash:5 -c "echo '$cloud_creds_data_enc' | base64 -d > /secrets/cloud_creds-\$(cat /environment_info/root_environment_id).yaml"

_generate_container_vol environment:
  set +u; \
  data=$(just _container_vol {{ environment }}); \
  shared=$(just _container_vol_shared); \
  for vol in "$data" "$shared"; \
  do \
    {{ container_bin }} volume ls | grep -q "$vol" && \
      test -z "$REBUILD_DATA_VOLUME" && \
      exit 0; \
    test -n "$REBUILD_DATA_VOLUME" && {{ container_bin }} volume rm -f "$vol" >/dev/null; \
    {{ container_bin }} volume create "$vol" >/dev/null; \
  done;

_ensure_container_image_exists environment:
  set +u; \
  image_name="$(just _container_image {{ environment }})";  \
  {{ container_bin }} images  | grep -q "$image_name" && \
    test -z "$REBUILD_IMAGE" && \
    exit 0; \
  container_file=$(just _get_property_from_env_config \
    {{ environment }} \
    '.deploy.container_file'); \
  test -z "$container_file" && \
    container_file=$(just _get_environment_directory_file {{ environment }} Containerfile); \
  if ! test -f "$container_file"; \
  then \
    just _log error "Containerfile not found at: $container_file"; \
    exit 1; \
  fi; \
  file_lines=$(cat "$container_file" | grep -Ev '^#|^FROM' | wc -l); \
  if test "$file_lines" -eq 0; \
  then \
    just _log error "Containerfile for '{{ environment }}' at '$container_file' is empty!"; \
    exit 1; \
  fi; \
  openshift_version=$(just _get_property_from_env_config_use_alias \
    {{ environment }} \
    '.deploy.cluster_config.openshift_version'); \
  test -z "$openshift_version" && openshift_version={{ default_openshift_version }}; \
  just _log info "(re)building deployer image '$image_name' [openshift version: $openshift_version]"; \
  {{ container_bin }} build -t "$image_name" \
    -f "$container_file" \
    --build-arg OPENSHIFT_VERSION="$openshift_version" \
    $PWD

_confirm_environment environment: \
    ( _confirm_environment_in_config environment ) \
    ( _confirm_environment_directory_exists environment ) \
    ( _confirm_environment_has_install_config environment )

_confirm_environment_has_install_config environment:
  ignore_installconfig_check=$(just _run_yq "$(grep -Ev '^[ ]{0,}#' {{ config_file }})" \
    '.environments["{{ environment}}"].common_options.ignore_installconfig_check'); \
  test "${ignore_installconfig_check,,}" == true && exit 0; \
  f="$(just _get_environment_directory '{{ environment }}')/include/templates/install-config.yaml"; \
  if ! test -f "$f"; \
  then \
    just _log error "{{ environment }} is missing an 'install-config.yaml' file in the include/templates directory."; \
    exit 1; \
  fi;

_confirm_environment_in_config environment:
  grep -q '^{{ environment }}$' <(just _run_yq "$(grep -Ev '^[ ]{0,}#' {{ config_file }})" '.environments | to_entries[] | .key') && \
    exit 0; \
  just _log error "Environment not in config: {{ environment }}"; \
  exit 1

_confirm_environment_directory_exists environment:
  test -f "$(just _get_environment_directory_file '{{ environment }}' 'provision.sh')" && exit 0; \
  just _log error "Environment directory doesn't exist: {{ environment }}"; \
  exit 1

_get_property_from_env_config environment key use_alias="false":
  if test "{{ use_alias }}" == 'true'; \
  then \
    config=$(just _merge_aliased_environment '{{ environment }}'); \
    key="{{ key }}"; \
  else \
    config=$(sops --decrypt "{{ source_dir() }}/config.yaml"); \
    key=$(printf '.environments["%s"].%s' \
      "{{ environment }}" \
      "$(sed -E 's/^\.//' <<< '{{ key }}')"); \
  fi; \
  echo "$config" | \
    yq -r "$key" | \
    grep -Ev '^null$' | \
    cat;

_get_property_from_env_config_use_alias environment key:
  just _get_property_from_env_config "{{ environment }}" "{{ key }}" "true"

_get_environment_directory environment:
  if test "{{ environment }}" == example; \
  then \
    just _get_environment_directory_no_alias example; \
    exit "$?"; \
  fi; \
  echo "{{ source_dir() }}/environments/$(just _resolved_environment_name '{{ environment }}')"

_get_environment_directory_no_alias environment:
  echo "{{ source_dir() }}/environments/{{ environment }}"

_get_environment_directory_file environment fp:
  printf "%s/%s" $(just _get_environment_directory "{{ environment }}") "{{ fp }}"

_toplevel_environment_kubeconfig environment:
  {{ container_bin }} run --rm \
      -v "$(just _container_secrets_vol_shared):/shared/secrets" \
      -v "$(just _container_environment_info_vol {{ environment }}):/environment_info" \
      bash:5 -c 'test -f /environment_info/kubeconfig_path && cat /environment_info/kubeconfig_path'

_run_yq input query:
  echo "{{ input }}" | {{ container_bin }} run --rm -i {{ yq_image }} '{{ query }}'

_do_yq_encoded_merge inputA inputB:
  {{ container_bin }} run --rm --entrypoint sh {{ yq_image }} -c \
     'yq eval-all ". as \$item ireduce ({}; . * \$item )" \
      <(echo "{{ inputA }}" | base64 -d) \
      <(echo "{{ inputB }}" | base64 -d)'

_sentinel_file name:
  topmost_pid() { \
    pid="${1:-$$}"; \
    last="${2:-$$}"; \
    comm=$(ps -p "$pid" -o command | grep -v 'COMMAND'); \
    test "$comm" == '-bash' && echo "$last" && return 0; \
    parent=$(ps -p $pid -o ppid= | tr -d ' '); \
    topmost_pid "$parent" "$pid"; \
  }; \
  echo "/tmp/demoland_temp_{{ name }}_$(topmost_pid)";


[positional-arguments]
_log level *message="No message?":
  case "${1,,}" in \
  error) \
    >&2 echo "{{ BOLD + UNDERLINE + RED }}${1^^}{{ NORMAL }}: ${@:2}"; \
    ;; \
  warn|warning) \
    >&2 echo "{{ BOLD + UNDERLINE + CYAN }}${1^^}{{ NORMAL }}: ${@:2}"; \
    ;; \
  info) \
    >&2 echo "{{ BOLD + UNDERLINE + GREEN }}${1^^}{{ NORMAL }}: ${@:2}"; \
    ;; \
  *) \
    >&2 echo "FATAL: invalid log level: $1"; \
    exit 1; \
    ;; \
  esac

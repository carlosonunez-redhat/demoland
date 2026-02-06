set shell := [ "bash", "-uc" ]
set unstable := true
set quiet := true

container_bin := env("CONTAINER_BIN", which('podman'))
container_image := 'demo-environment-runner'
container_vol := 'demo-environment-runner-vol'
container_secrets_vol := 'demo-environment-runner-secrets-vol'
config_file := source_dir() + '/config.yaml'
yq_image := 'mikefarah/yq'

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

[doc("Deploys an environment")]
deploy environment: (_deploy_with_dependencies environment )

[doc("Runs preflight checks defined in an environment, if any.")]
precheck environment:
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

[doc("Exposes secrets created by the environment, if any.")]
expose environment:
  just _execute_containerized '{{ environment }}' \
    'expose.sh' \
    'true' \
    'Environment {{ environment }} does not have anything to expose; skipping.';



[doc("Provisions an environment")]
provision environment:
  just _execute_containerized '{{ environment }}' 'provision.sh';


[doc("Destroys an environment")]
destroy environment:
  just _execute_containerized '{{ environment }}' 'destroy.sh';

_deploy_with_dependencies environment:
  set +u; \
  if test -n "$SKIP_DEPENDENCIES"; \
  then envs="{{ environment }}"; \
  else envs="$(just _get_dependent_environments {{ environment }});{{ environment }}"; \
  fi; \
  set -eu; \
  for env in $(echo "$envs" | sed -E 's/^;//' | tr ';' '\n'); \
  do just _confirm_environment "$env" || exit 1; \
  done; \
  for env in $(echo "$envs" | sed -E 's/^;//' | tr ';' '\n'); \
  do \
    for stage in precheck provision expose; \
    do \
      if test "$env" != '{{ environment }}'; \
      then just _log info "Running operation [$stage] on dependent environment [$env]"; \
      else just _log info "Running operation [$stage] on environment [$env]"; \
      fi; \
      just "$stage" "$env"; \
    done; \
  done

_get_dependent_environments environment:
  set +u; \
  env_data=$(sops --decrypt --extract '["environments"]["{{ environment }}"]' \
    --output-type yaml "{{ config_file }}") || exit 1; \
  just _run_yq "$env_data" '.depends_on | join(";")' | grep -Ev '^null$'; \
  exit 0;

_environment_name environment:
  echo '{{ environment }}' | tr ' ' '_'

_resolved_environment_name environment: (_confirm_environment_in_config environment)
  set +u; \
  env_data=$(sops --decrypt --extract '["environments"]["{{ environment }}"]' \
    --output-type yaml "{{ config_file }}") || exit 1; \
  alias=$(just _run_yq "$env_data" '.alias_of'); \
  if test -z "$alias" || test "$alias" == 'null'; \
  then echo '{{ environment }}' && exit 0; \
  fi; \
  echo "$alias";

_create_new_env_dir_structure environment:
  cp -r "$(just _get_environment_directory 'example')" \
    "$(just _get_environment_directory '{{ environment }}')"

_delete_env_dir environment:
  rm -r "$(just _get_environment_directory '{{ environment }}')"

_add_env_to_config environment:
  conf=$(sops --decrypt --extract '["environments"]["example"]' \
    --output-type json {{ config_file }}); \
  sops set {{ config_file }} '["environments"]["{{ environment }}"]' "$conf"

_delete_env_from_config environment:
  sops unset {{ config_file }} '["environments"]["{{ environment }}"]'

_container_vol environment:
  env=$(just _resolved_environment_name '{{ environment }}'); \
  echo "{{ container_vol }}-$env"

_container_secrets_vol environment:
  env=$(just _resolved_environment_name '{{ environment }}'); \
  echo "{{ container_secrets_vol }}-$env"

_container_vol_shared environment:
  env=$(just _resolved_environment_name '{{ environment }}'); \
  echo "{{ container_vol }}-shared-$env"

_container_secrets_vol_shared environment:
  env=$(just _resolved_environment_name '{{ environment }}'); \
  echo "{{ container_secrets_vol }}-shared-$env"

_container_image environment:
  env=$(just _resolved_environment_name '{{ environment }}'); \
  echo "{{ container_image }}-$env"

_execute_containerized environment file ignore_not_found='false' custom_message='none': \
    ( _ensure_container_image_exists environment ) \
    ( _ensure_container_volume_exists environment ) \
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
  command=({{ container_bin }} run --rm -it \
    -v "$(just _container_vol {{ environment }}):/data" \
    -v "$(just _container_secrets_vol {{ environment }}):/secrets" \
    -v "$(just _container_vol_shared {{ environment }}):/shared/data" \
    -v "$(just _container_secrets_vol_shared {{ environment }}):/shared/secrets" \
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
    --output-type yaml "{{ config_file }}") || exit 1; \
  env_data_enc=$(base64 -w 0 <<< $env_data); \
  alias=$(just _run_yq "$env_data" '.alias_of'); \
  if test -z "$alias" || test "$alias" == 'null'; \
  then echo "$env_data" && exit 0; \
  fi; \
  q=$(printf '["environments"]["%s"]' "$alias"); \
  target_env_data=$(sops --decrypt --extract "$q" --output-type yaml "{{ config_file }}") || exit 1; \
  target_env_data_enc=$(base64 -w 0 <<< $target_env_data); \
  just _do_yq_encoded_merge "$target_env_data_enc" "$env_data_enc"

_ensure_container_secrets_vol_populated environment:
  set +u; \
  vol=$(just _container_secrets_vol {{ environment }}); \
  if test -n "$REBUILD_SECRETS_VOLUME" || \
    test -n "$({{ container_bin }} volume ls | grep -q "$vol")"; \
  then \
    test -n "$REBUILD_SECRETS_VOLUME" && {{ container_bin }} volume rm -f "$vol" >/dev/null; \
    {{ container_bin }} volume create "$vol" >/dev/null; \
  fi; \
  env_data=$(just _merge_aliased_environment '{{ environment }}'); \
  env_data_enc=$(base64 -w 0 <<< "$env_data"); \
  {{ container_bin }} run --rm \
    -v "$vol:/secrets" \
    bash:5 -c "echo '$env_data_enc' | base64 -d > /secrets/config.yaml"; \
  set -eu; \
  for secret in "$(echo "$env_data" | yq -r '.secrets | to_entries[]' | grep -Ev '^null$')"; \
  do \
    fname=$(yq -r '.value.name' <<< "$secret" | grep -Ev '^null$'); \
    secret_data_enc=$(yq -r '.value.data | @base64' <<< "$secret"); \
    {{ container_bin }} run --rm \
      -v "$vol:/secrets" \
      bash:5 -c "test -f /secrets/$fname && exit 0; echo '$secret_data_enc' |base64 -d > /secrets/$fname"; \
  done;

_ensure_container_volume_exists environment:
  set +u; \
  data=$(just _container_vol {{ environment }}); \
  shared=$(just _container_vol_shared {{ environment }}); \
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
    just _log info "(re)building deployer image '$image_name'"; \
    {{ container_bin }} build -t "$image_name" \
      -f "$container_file" \
      $PWD

_confirm_environment environment: \
    ( _confirm_environment_in_config environment ) \
    ( _confirm_environment_directory_exists environment ) \
    ( _confirm_environment_has_install_config environment )

_confirm_environment_has_install_config environment:
  ignore_installconfig_check=$(just _run_yq "$(cat {{ config_file }})" \
    '.environments["{{ environment}}"].common_options.ignore_installconfig_check'); \
  test "${ignore_installconfig_check,,}" == true && exit 0; \
  f="$(just _get_environment_directory '{{ environment }}')/include/templates/install-config.yaml"; \
  if ! test -f "$f"; \
  then \
    just _log error "{{ environment }} is missing an 'install-config.yaml' file in the include/templates directory."; \
    exit 1; \
  fi;

_confirm_environment_in_config environment:
  grep -q '^{{ environment }}$' <(just _run_yq "$(cat {{ config_file }})" '.environments | to_entries[] | .key') && \
    exit 0; \
  just _log error "Environment not in config: {{ environment }}"; \
  exit 1

_confirm_environment_directory_exists environment:
  test -f "$(just _get_environment_directory_file '{{ environment }}' 'provision.sh')" && exit 0; \
  just _log error "Environment directory doesn't exist: {{ environment }}"; \
  exit 1

_get_property_from_env_config environment key:
  env=$(just _resolved_environment_name '{{ environment }}'); \
  key=$(echo {{ key }} | \
    sed -E 's/^\.//' | \
    tr '.[]' '\n' | \
    grep -Ev '^$' | \
    sed -E 's;(.*);["\1"];g' | \
    sed -E 's;"([0-9]+)";\1;g' | \
    tr -d '\n'); \
  key='["environments"]["'"$env"'"]'"$key"; \
  sops --decrypt --extract "$key" "{{ source_dir() }}/config.yaml" 2>/dev/null || true;

_get_environment_directory environment:
  echo "{{ source_dir() }}/environments/$(just _environment_name '{{ environment }}')"

_get_environment_directory_file environment fp:
  printf "%s/%s" $(just _get_environment_directory "{{ environment }}") "{{ fp }}"

_run_yq input query:
  echo "{{ input }}" | {{ container_bin }} run --rm -i {{ yq_image }} '{{ query }}'

_do_yq_encoded_merge inputA inputB:
  {{ container_bin }} run --rm --entrypoint sh {{ yq_image }} -c \
     'yq eval-all ". as \$item ireduce ({}; . * \$item )" \
      <(echo "{{ inputA }}" | base64 -d) \
      <(echo "{{ inputB }}" | base64 -d)'


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

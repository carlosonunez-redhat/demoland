set shell := [ "bash", "-uc" ]
set unstable := true
set quiet := true

container_bin := env("CONTAINER_BIN", which('podman'))
container_image := 'demo-environment-runner'
container_vol := 'demo-environment-runner-vol'
container_secrets_vol := 'demo-environment-runner-secrets-vol'
config_file := source_dir() + '/config.yaml'
yq_image := 'mikefarah/yq'

[doc("Deploys an environment")]
deploy environment: (_confirm_environment environment) \
    (precheck environment) \
    (provision environment)

[doc("Runs preflight checks defined in an environment, if any.")]
precheck environment:
  just _execute_containerized '{{ environment }}' \
    'preflight.sh' \
    'true' \
    'Environment {{ environment }} does not have preflight checks; skipping.';

[doc("Provisions an environment")]
provision environment:
  just _execute_containerized '{{ environment }}' 'provision.sh';

[doc("Creates a new environment")]
create_new_environment environment:
  env=$(echo '{{ environment }}' | tr ' ' '_'); \
  if test -d "$(just _get_environment_directory '{{ environment }}')"; \
  then \
    just _log error "Environment already exists; delete to recreate it: $env"; \
    exit 1; \
  fi; \
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

[doc("Destroys an environment")]
destroy environment:
  just _execute_containerized '{{ environment }}' 'destroy.sh';


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
  echo "{{ container_vol }}-{{ environment }}"

_container_secrets_vol environment:
  echo "{{ container_secrets_vol }}-{{ environment }}"

_container_image environment:
  echo "{{ container_image }}-{{ environment }}"

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
    -v $PWD/include:/app/include \
    -v "$(just _get_environment_directory {{ environment }}):/app/environment" \
    -w /app); \
  while read var; \
  do command+=(-e "$var"); \
  done < <(just _run_yq \
    "$(just _get_property_from_env_config {{ environment }} '.deploy.environment_vars')" \
    '.[]'); \
  command+=($(just _container_image {{ environment }}) /app/environment/{{ file }}); \
  "${command[@]}"

_ensure_container_secrets_vol_populated environment:
  set +u; \
  vol=$(just _container_vol {{ environment }}); \
  if test -n "$REBUILD_SECRETS_VOLUME" || \
    test -n "$({{ container_bin }} volume ls | grep -q "$vol")"; \
  then \
    test -n "$REBUILD_SECRETS_VOLUME" && {{ container_bin }} volume rm -f "$vol" >/dev/null; \
    {{ container_bin }} volume create "$vol" >/dev/null; \
  fi; \
  env_data=$(sops --decrypt --extract '["environments"]["{{ environment }}"]' \
    --output-type yaml "{{ config_file }}") || exit 1; \
  env_data_enc=$(base64 -w 0 <<< "$env_data"); \
  {{ container_bin }} run --rm \
    -v "$(just _container_secrets_vol {{ environment }}):/data" \
    bash:5 -c "echo '$env_data_enc' | base64 -d > /data/config.yaml"

_ensure_container_volume_exists environment:
  set +u; \
  vol=$(just _container_vol {{ environment }}); \
  {{ container_bin }} volume ls | grep -q "$vol" && \
    test -z "$REBUILD_DATA_VOLUME" && \
    exit 0; \
  test -n "$REBUILD_DATA_VOLUME" && {{ container_bin }} volume rm -f "$vol" >/dev/null; \
  {{ container_bin }} volume create "$vol" >/dev/null;

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
    ( _confirm_environment_directory_exists environment ) \
    ( _confirm_environment_has_install_config environment ) \
    ( _confirm_environment_in_config environment )

_confirm_environment_has_install_config environment:
  f="$(just _get_environment_directory '{{ environment }}')/install-config.yaml"; \
  if ! test -f "$f"; \
  then \
    just _log error "{{ environment }} is missing an 'install-config.yaml' file."; \
    exit 1; \
  fi;

_confirm_environment_in_config environment:
  just _run_yq "$(cat {{ config_file }})" '.environments | to_entries[] | .key' | \
    grep -q '^{{ environment }}$' && exit 0; \
  just _log error "Environment not in config: {{ environment }}"; \
  exit 1

_confirm_environment_directory_exists environment:
  test -f "$(just _get_environment_directory_file '{{ environment }}' 'provision.sh')" && exit 0; \
  _just log error "Environment directory doesn't exist: {{ environment }}"; \
  exit 1

_get_property_from_env_config environment key:
  key=$(echo {{ key }} | \
    sed -E 's/^\.//' | \
    tr '.[]' '\n' | \
    grep -Ev '^$' | \
    sed -E 's;(.*);["\1"];g' | \
    sed -E 's;"([0-9]+)";\1;g' | \
    tr -d '\n'); \
  key='["environments"]["{{ environment }}"]'"$key"; \
  sops --decrypt --extract "$key" "{{ source_dir() }}/config.yaml" 2>/dev/null || true;

_get_environment_directory environment:
  echo "{{ source_dir() }}/environments/{{ environment }}"

_get_environment_directory_file environment fp:
  printf "%s/%s" $(just _get_environment_directory "{{ environment }}") "{{ fp }}"

_run_yq input query:
  echo "{{ input }}" | {{ container_bin }} run --rm -i {{ yq_image }} '{{ query }}'

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

set shell := [ "bash", "-uc" ]
set unstable := true
set quiet := true

container_bin := env("CONTAINER_BIN", which('podman'))
container_image := 'demo-environment-runner'
container_vol := 'demo-environment-runner-vol'
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

[doc("Destroys an environment")]
destroy environment:
  just _execute_containerized '{{ environment }}' 'destroy.sh';

_container_vol environment:
  echo "{{ container_vol }}-{{ environment }}"

_container_image environment:
  echo "{{ container_image }}-{{ environment }}"

_execute_containerized environment file ignore_not_found='false' custom_message='none': \
    ( _ensure_container_image_exists environment ) \
    ( _ensure_container_volume_exists environment )
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
  command=({{ container_bin }} run --rm \
    -v "$(just _container_vol {{ environment }}):/data" \
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

_ensure_container_volume_exists environment:
  set +u; \
  vol=$(just _container_vol {{ environment }}); \
  {{ container_bin }} volume ls | grep -q "$vol" && \
    test -z "$REBUILD_DATA_VOLUME" && \
    exit 0; \
  test -n "$REBUILD_DATA_VOLUME" && {{ container_bin }} volume rm -f "$vol"; \
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
    ( _confirm_environment_in_config environment )

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
  echo "{{ source_dir() }}/{{ environment }}"

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

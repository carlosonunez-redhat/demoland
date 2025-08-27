set shell := [ "bash", "-uc" ]
set unstable := true
set quiet := true

config_file := "{{ source_dir() }}/config.yaml"
container_bin := env("CONTAINER_BIN", which('podman'))

[doc("Deploys an environment")]
deploy environment: (_confirm_environment environment) \
    (precheck environment) \
    (provision environment)

[doc("Provisions an environment")]
provision environment:
  $(just _get_environment_directory_file '{{ environment }}' 'provision.sh'

[doc("Runs preflight checks defined in an environment, if any.")]
precheck environment:
  pfc_file="$(just _get_environment_directory_file '{{ environment }}' 'preflight.sh')"; \
  test -f "$pfc_file" && { "$pfc_file" ; exit $?; }; \
  just _log info "{{ environment }} does not have any preflight checks; continuing."

_confirm_environment environment: \
    ( _confirm_environment_directory_exists environment ) \
    ( _confirm_environment_in_config environment )

_confirm_environment_in_config environment:
  {{ container_bin }} run --rm -v "$PWD/config.yaml:/config.yaml" \
      mikefarah/yq -r '.environments | to_entries[] | .key' \
      /config.yaml | grep -q "^{{ environment }}$" && exit 0; \
  >&2 echo "{{ style("error") }}Environment not in config: {{ environment }}"; \
  exit 1

_confirm_environment_directory_exists environment:
  test -f "$(just _get_environment_directory_file '{{ environment }}' 'provision.sh')" && exit 0; \
  >&2 echo "{{ style("error") }}Environment directory doesn't exist: {{ environment }}"; \
  exit 1

_get_environment_directory environment:
  echo "{{ source_dir() }}/{{ environment }}"

_get_environment_directory_file environment fp:
  printf "%s/%s" $(just _get_environment_directory "{{ environment }}") "{{ fp }}"

_get_environment_config environment:
  sops --extract '["environments"]["{{ environment }}"]' {{ config_file }}

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

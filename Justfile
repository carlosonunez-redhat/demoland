set shell := [ "bash", "-uc" ]
set unstable := true
set quiet := true

config_file := "{{ source_dir() }}/config.yaml"
container_bin := env("CONTAINER_BIN", which('podman'))

[doc("Deploys an environment")]
deploy environment: (confirm_environment environment)


[private]
confirm_environment environment: \
    ( confirm_environment_in_directory environment ) \
    ( confirm_environment_in_config environment )

[private]
confirm_environment_in_config environment:
  {{ container_bin }} run --rm -v "$PWD/config.yaml:/config.yaml" \
      mikefarah/yq -r '.environments | to_entries[] | .key' \
      /config.yaml | grep -q "^{{ environment }}$" && exit 0; \
  >&2 echo "{{ style("error") }}Environment not in config: {{ environment }}"; \
  exit 1

[private]
confirm_environment_in_directory environment:
  find "{{ source_dir() }}" -type d -maxdepth 1 | \
    grep -Eq '/{{ environment }}$' && exit 0; \
  >&2 echo "{{ style("error") }}Environment directory doesn't exist: {{ environment }}"; \
  exit 1

[private]
get_environment_config environment:
  sops --extract '["environments"]["{{ environment }}"]' {{ config_file }}


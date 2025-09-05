# shellcheck shell=bash

as_csv() {
  tr '\n' ',' < /dev/stdin | sed -E 's/,$//'
}

as_json_string() {
  jq tostring /dev/stdin
}

_template_file() {
  printf "%s/include/templates/%s.yaml" \
    "$(dirname "$0")" \
    "${1//.y*ml/}"
}

as_yaml_list() {
  local ls
  while read -r elem
  do ls="${ls},\"${elem}\""
  done < /dev/stdin
  printf '[%s]' "$(sed -E 's/^,//' <<< "$ls")"
}

render_yaml_template() {
  local file cmd
  file="$(_template_file "$1")"
  if ! test -f "$file"
  then
    error "YAML template not found: $file"
    return 1
  fi
  shift
  cmd=(ytt)
  while test "$#" -ne 0
  do
    cmd+=(--data-value-yaml "$1=$2")
    shift; shift
  done
  cmd+=(-f "$file")
  "${cmd[@]}"
}

render_yaml_template_with_values_file() {
  local file values_file
  file=$(_template_file "$1")
  values_file="$2"
  for f in "$file" "$values_file"
  do
    test -f "$f" && continue
    error "YAML file or template not found: $f"
    return 1
  done
  ytt --data-values-file "$values_file" -f "$file"

}

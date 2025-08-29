fail_if_nil() {
  if test -n "$1"
  then
    echo "$1"
    return 0
  fi
  error "$2"
  return 1
}

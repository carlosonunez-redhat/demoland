# shellcheck shell=bash
resolve_this_ip() {
  result=$(2>/dev/null curl -sS http://api.ipify.org)
  if test -n "$result" && grep -Eq '^([0-9]{1,3}.){3}[0-9]{1,3}$' <<< "$result"
  then
    echo "$result"
    return
  fi
  return 1
}

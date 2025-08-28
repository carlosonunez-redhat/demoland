# shellcheck shell=bash
BRed='\033[1;31m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BCyan='\033[1;36m'
RESET="\033[m"

_log() {
  local level message color
  level="$1"
  message="$2"
  case "${level,,}" in
    debug) color="$BCyan"; ;;
    error) color="$BRed"; ;;
    warning) color="$BYellow"; ;;
    info) color="$BGreen"; ;;
    *)
      >&2 echo -e "${BRed}FATAL${RESET}: Invalid level: $level"
      exit 1;
      ;;
  esac
  >&2 echo -e "${color}${level^^}${RESET}: $message"
}

info() { _log info "$1" ; }
warning() { _log warning "$1" ; }
error() { _log error "$1" ; }
debug() { _log debug "$1" ; }

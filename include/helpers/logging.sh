# shellcheck shell=bash
BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
BYellow='\033[1;33m'      # Yellow
RESET="\033[m"               # Color Reset

_log() {
  local level message color
  level="$1"
  message="$2"
  case "${level,,}" in
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

# wing env stdlib
#
# Trimmed adaptation of direnv's stdlib.sh, providing the helpers available
# inside a .envrc evaluation context. direnv is licensed under the MIT license
# (Copyright (C) @zimbatm and contributors). See https://github.com/direnv/direnv
#
# This file is sourced by wing inside a bash subshell BEFORE the user's
# .envrc. Functions defined here are usable from .envrc.
#
# wing passes these variables to the subshell:
#   WING_BIN         absolute path to the wing binary
#   WING_ENVRC       absolute path to the .envrc being evaluated
#   WING_WATCH_FILE  path to a file that watch_file/watch_dir append to
#
# Compatibility shim: $direnv points at the wing binary so .envrc files
# originally written for direnv that reference "$direnv" keep working for the
# operations wing implements.

shopt -s gnu_errfmt nullglob extglob

direnv="$WING_BIN"
direnv_config_dir="${DIRENV_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/wing}"
export DIRENV_IN_ENVRC=1

__env_strictness() {
  local mode tmpfile old_shell_options res
  tmpfile="$(mktemp)"
  res=0
  mode="$1"
  shift
  set +o | grep 'pipefail\|nounset\|errexit' >"$tmpfile"
  old_shell_options=$(<"$tmpfile")
  rm -f "$tmpfile"
  case "$mode" in
  strict) set -o errexit -o nounset -o pipefail ;;
  unstrict) set +o errexit +o nounset +o pipefail ;;
  *) log_error "Unknown strictness mode '${mode}'."; exit 1 ;;
  esac
  if (($#)); then "${@}"; res=$?; eval "$old_shell_options"; fi
  if [[ $mode = strict && $res -gt 0 ]]; then exit 1; fi
  return $res
}

strict_env() { __env_strictness strict "$@"; }
unstrict_env() {
  if (($#)); then __env_strictness unstrict "$@"
  else set +o errexit +o nounset +o pipefail; fi
}

direnv_layout_dir() { echo "${direnv_layout_dir:-$PWD/.direnv}"; }

log_status() { echo "wing env: $*" >&2; }
log_error() { echo "wing env: ERROR $*" >&2; }

has() { type "$1" &>/dev/null; }

realpath.dirname() {
  REPLY=.
  ! [[ $1 =~ /+[^/]+/*$|^//$ ]] || REPLY="${1%"${BASH_REMATCH[0]}"}"
  REPLY=${REPLY:-/}
}
realpath.basename() {
  REPLY=/
  ! [[ $1 =~ /*([^/]+)/*$ ]] || REPLY="${BASH_REMATCH[1]}"
}
realpath.absolute() {
  REPLY=$PWD
  local eg=extglob
  ! shopt -q $eg || eg=
  ${eg:+shopt -s $eg}
  while (($#)); do case $1 in
    // | //[^/]*) REPLY=//; set -- "${1:2}" "${@:2}" ;;
    /*) REPLY=/; set -- "${1##+(/)}" "${@:2}" ;;
    */*) set -- "${1%%/*}" "${1##"${1%%/*}"+(/)}" "${@:2}" ;;
    '' | .) shift ;;
    ..) realpath.dirname "$REPLY"; shift ;;
    *) REPLY="${REPLY%/}/$1"; shift ;;
    esac done
  ${eg:+shopt -u $eg}
}

expand_path() {
  local REPLY
  realpath.absolute "${2+"$2"}" "${1+"$1"}"
  echo "$REPLY"
}

user_rel_path() {
  local abs_path=${1#-}
  if [[ -z $abs_path ]]; then return; fi
  if [[ -n $HOME ]]; then
    local rel_path=${abs_path#"$HOME"}
    if [[ $rel_path != "$abs_path" ]]; then abs_path=~$rel_path; fi
  fi
  echo "$abs_path"
}

find_up() {
  (
    while true; do
      if [[ -f $1 ]]; then echo "$PWD/$1"; return 0; fi
      if [[ $PWD == / || $PWD == // ]]; then return 1; fi
      cd ..
    done
  )
}

path_add() {
  local path i var_name="$1"
  declare -a path_array
  IFS=: read -ra path_array <<<"${!1-}"
  shift
  for ((i = $#; i > 0; i--)); do
    path_array=("$(expand_path "${!i}")" ${path_array[@]+"${path_array[@]}"})
  done
  path=$(
    IFS=:
    echo "${path_array[*]}"
  )
  export "$var_name=$path"
}

PATH_add() { path_add PATH "$@"; }

MANPATH_add() {
  local old_paths="${MANPATH:-$(man -w 2>/dev/null)}"
  local dir
  dir=$(expand_path "$1")
  export "MANPATH=$dir:$old_paths"
}

path_rm() {
  local path discard var_name="$1"
  declare -a path_array
  IFS=: read -ra path_array <<<"${!1}"
  shift
  local patterns=("$@") results=()
  for path in ${path_array[@]+"${path_array[@]}"}; do
    discard=false
    for pattern in ${patterns[@]+"${patterns[@]}"}; do
      if [[ "$path" == +($pattern) ]]; then discard=true; break; fi
    done
    if ! $discard; then results+=("$path"); fi
  done
  path=$(
    IFS=:
    echo "${results[*]}"
  )
  export "$var_name=$path"
}

PATH_rm() { path_rm PATH "$@"; }

load_prefix() {
  local REPLY
  realpath.absolute "$1"
  MANPATH_add "$REPLY/man" 2>/dev/null || true
  MANPATH_add "$REPLY/share/man" 2>/dev/null || true
  path_add CPATH "$REPLY/include"
  path_add LD_LIBRARY_PATH "$REPLY/lib"
  path_add LIBRARY_PATH "$REPLY/lib"
  path_add PATH "$REPLY/bin"
  path_add PKG_CONFIG_PATH "$REPLY/lib/pkgconfig"
}

__wing_dotenv() {
  local load=$1 path=${2:-}
  if [[ -z $path ]]; then path=$PWD/.env
  elif [[ -d $path ]]; then path=$path/.env; fi
  watch_file "$path"
  if ! [[ -f $path ]]; then
    if $load; then log_error ".env at $path not found"; return 1; fi
    return 0
  fi
  set -a
  # shellcheck disable=SC1090
  source "$path"
  set +a
}

dotenv() { __wing_dotenv true "${1:-}"; }
dotenv_if_exists() { __wing_dotenv false "${1:-}"; }

watch_file() {
  if [[ -n $WING_WATCH_FILE ]]; then
    local f
    for f in "$@"; do echo "$f" >>"$WING_WATCH_FILE"; done
  fi
}

watch_dir() {
  if [[ -n $WING_WATCH_FILE ]]; then echo "dir:$1" >>"$WING_WATCH_FILE"; fi
}

source_env() {
  local rcpath=${1/#\~/$HOME}
  if has cygpath; then rcpath=$(cygpath -u "$rcpath"); fi
  local REPLY
  if [[ -d $rcpath ]]; then rcpath=$rcpath/.envrc; fi
  if [[ ! -e $rcpath ]]; then log_status "referenced $rcpath does not exist"; return 1; fi
  realpath.dirname "$rcpath"; local rcpath_dir=$REPLY
  realpath.basename "$rcpath"; local rcpath_base=$REPLY
  watch_file "$rcpath"
  pushd "$(pwd 2>/dev/null)" >/dev/null || return 1
  pushd "$rcpath_dir" >/dev/null || return 1
  if [[ -f ./$rcpath_base ]]; then
    log_status "loading $(user_rel_path "$(expand_path "$rcpath_base")")"
    # shellcheck disable=SC1090
    . "./$rcpath_base"
  else
    log_status "referenced $rcpath does not exist"
  fi
  popd >/dev/null || return 1
  popd >/dev/null || return 1
}

source_env_if_exists() {
  watch_file "$1"
  if [[ -f "$1" ]]; then source_env "$1"; fi
}

_source_up() {
  local envrc file=${1:-.envrc} ok_if_not_exist=${2}
  envrc=$(cd .. && (find_up "$file" || true))
  if [[ -n $envrc ]]; then source_env "$envrc"
  elif $ok_if_not_exist; then return 0
  else log_error "No ancestor $file found"; return 1; fi
}

source_up() { _source_up "${1:-}" false; }
source_up_if_exists() { _source_up "${1:-}" true; }

direnv_version() {
  if [[ -z ${1:-} ]]; then echo "2.37.1-wing"; return; fi
  # Best-effort version check; wing reports a direnv-compatible version.
  return 0
}

layout() { log_status "layout '$1' is not supported by wing env (yet)"; }
use() { log_status "use '$1' is not supported by wing env (yet)"; }
direnv_load() { log_error "direnv_load is not supported by wing env"; return 1; }

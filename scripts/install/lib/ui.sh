#!/usr/bin/env bash
# gum wrappers used by every module. UI_MODE falls back to plain read/echo
# prompts for the handful of steps (system update, dependency install) that
# necessarily run before gum itself is installed.
UI_MODE="plain"

ui::init() {
  if command -v gum >/dev/null 2>&1; then
    UI_MODE="gum"
  else
    UI_MODE="plain"
  fi
}

ui::header() {
  if [ "$UI_MODE" = "gum" ]; then
    gum style --border normal --margin "1 0" --padding "0 2" --border-foreground 212 "$1"
  else
    printf '\n== %s ==\n' "$1"
  fi
}

ui::info() {
  if [ "$UI_MODE" = "gum" ]; then
    gum style --foreground 39 "$1"
  else
    printf 'info: %s\n' "$1"
  fi
}

ui::warn() {
  if [ "$UI_MODE" = "gum" ]; then
    gum style --border normal --border-foreground 214 --foreground 214 --padding "0 1" "$1"
  else
    printf 'warn: %s\n' "$1"
  fi
}

ui::error() {
  if [ "$UI_MODE" = "gum" ]; then
    gum style --border normal --border-foreground 196 --foreground 196 --padding "0 1" "$1"
  else
    printf 'error: %s\n' "$1" >&2
  fi
}

ui::success() {
  if [ "$UI_MODE" = "gum" ]; then
    gum style --foreground 42 "✓ $1"
  else
    printf 'ok: %s\n' "$1"
  fi
}

# ui::confirm "question" [default(0=yes,1=no)]
ui::confirm() {
  local question="$1"
  local default="${2:-0}"

  if [ "${PVC_NONINTERACTIVE:-0}" = "1" ]; then
    return "$default"
  fi

  if [ "$UI_MODE" = "gum" ]; then
    if [ "$default" = "0" ]; then
      gum confirm "$question"
    else
      gum confirm --default=false "$question"
    fi
    return $?
  fi

  local suffix="[y/N]"
  [ "$default" = "0" ] && suffix="[Y/n]"
  local reply
  read -r -p "$question $suffix " reply || true
  reply="${reply:-}"
  if [ -z "$reply" ]; then
    return "$default"
  fi
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# ui::input "prompt" "default_value" ["--password"]
ui::input() {
  local prompt="$1"
  local default="${2:-}"
  local password="${3:-}"

  if [ "$UI_MODE" = "gum" ]; then
    if [ "$password" = "--password" ]; then
      gum input --password --placeholder "$prompt" --value "$default"
    else
      gum input --placeholder "$prompt" --value "$default"
    fi
    return
  fi

  local reply
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply || true
    echo "${reply:-$default}"
  else
    read -r -p "$prompt: " reply || true
    echo "$reply"
  fi
}

# ui::choose "prompt" opt1 opt2 ... -> echoes the chosen option
ui::choose() {
  local prompt="$1"
  shift
  if [ "$UI_MODE" = "gum" ]; then
    gum choose --header "$prompt" "$@"
    return
  fi

  printf '%s\n' "$prompt" >&2
  local i=1
  for opt in "$@"; do
    printf '  %d) %s\n' "$i" "$opt" >&2
    i=$((i + 1))
  done
  local reply
  read -r -p "> " reply || true
  local idx=1
  for opt in "$@"; do
    if [ "$idx" = "$reply" ]; then
      echo "$opt"
      return
    fi
    idx=$((idx + 1))
  done
  # Fall back to treating the raw input as the answer (e.g. typed it verbatim).
  echo "$reply"
}

# ui::spin "message" -- command args...
ui::spin() {
  local message="$1"
  shift
  [ "$1" = "--" ] && shift

  if [ "$UI_MODE" = "gum" ]; then
    gum spin --title "$message" -- "$@"
    return $?
  fi

  printf '... %s\n' "$message"
  "$@"
}

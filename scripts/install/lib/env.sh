#!/usr/bin/env bash
# .env read/write helpers. Deliberately doesn't `source` the file (a
# tampered/corrupted .env shouldn't be able to execute arbitrary code) and
# preserves comments/ordering when editing a single key, since
# .env.example's comments are meant to stay readable documentation.

declare -gA ENV_VALUES=()

env::exists() {
  local file="${1:-.env}"
  [ -f "$file" ]
}

# Parses KEY=VALUE lines (ignoring comments/blank lines) into ENV_VALUES.
env::load() {
  local file="${1:-.env}"
  ENV_VALUES=()
  [ -f "$file" ] || return 0
  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    # Only accept simple KEY=VALUE lines — anything else is ignored rather
    # than evaluated.
    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      ENV_VALUES["$key"]="$value"
    fi
  done < "$file"
}

env::get() {
  local key="$1" default="${2:-}"
  echo "${ENV_VALUES[$key]:-$default}"
}

# env::set <file> <key> <value> — replaces an existing KEY=... line in
# place, or appends one if the key doesn't exist yet. Everything else in
# the file (comments, blank lines, ordering) is left untouched.
env::set() {
  local file="$1" key="$2" value="$3"
  local tmp
  tmp="$(mktemp)"
  local found=0

  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" =~ ^${key}= ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
        found=1
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$file"
  fi

  if [ "$found" -eq 0 ]; then
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi

  mv "$tmp" "$file"
  chmod 600 "$file"
  ENV_VALUES["$key"]="$value"
}

env::generate_secret() {
  openssl rand -hex 32
}

# env::render_from_example <example_file> <dest_file>
env::render_from_example() {
  local example="$1" dest="$2"
  if [ -f "$dest" ]; then
    return 0
  fi
  cp "$example" "$dest"
  chmod 600 "$dest"
}

# Rejects the case where required keys are still the literal placeholder
# values shipped in .env.example — catches "user never actually edited it."
env::validate() {
  local file="${1:-.env}"
  [ -f "$file" ] || { ui::error ".env not found at $file"; return 1; }
  env::load "$file"

  local required=(DOMAIN PRIMARY_IP TURN_DOMAIN TURN_SECOND_IP TURN_REALM TURN_SHARED_SECRET)
  local placeholders=(
    "DOMAIN=call.example.com"
    "PRIMARY_IP=203.0.113.1"
    "TURN_DOMAIN=turn.example.com"
    "TURN_SECOND_IP=203.0.113.10"
    "TURN_SHARED_SECRET=change-me-to-a-long-random-value"
  )

  local key
  for key in "${required[@]}"; do
    if [ -z "${ENV_VALUES[$key]:-}" ]; then
      ui::error "Missing required .env value: $key"
      return 1
    fi
  done

  local ph pk pv
  for ph in "${placeholders[@]}"; do
    pk="${ph%%=*}"
    pv="${ph#*=}"
    if [ "${ENV_VALUES[$pk]:-}" = "$pv" ]; then
      ui::error "$pk is still the placeholder value from .env.example — it needs to be set for real."
      return 1
    fi
  done

  return 0
}

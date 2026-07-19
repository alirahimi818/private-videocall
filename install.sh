#!/usr/bin/env bash
# Entry point for: curl -fsSL <raw-url>/install.sh | bash
#
# Deliberately tiny and dependency-free — a script piped through `bash` has
# no filesystem identity, so it can't `source` sibling files that don't
# exist on disk yet. This does the minimum needed to get a real checkout of
# the repo on disk, then re-execs into the real, modular installer from
# there (see scripts/install/main.sh), where sourcing lib/*.sh and
# modules/*.sh by relative path is safe.
set -euo pipefail

REPO_URL="${PVC_REPO_URL:-https://github.com/alirahimi818/private-videocall.git}"
REPO_BRANCH="${PVC_REPO_BRANCH:-main}"
INSTALL_DIR="${PVC_INSTALL_DIR:-/opt/private-videocall}"

log() { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# Root check — re-exec under sudo rather than fail outright, since the
# curl-pipe-bash invocation itself can't be re-run interactively by the user
# with sudo prepended (they'd have to retype the whole curl command).
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    log "Re-running as root via sudo..."
    exec sudo -E bash "$0" "$@"
  else
    die "This installer must run as root, and sudo isn't available. Re-run as root directly."
  fi
fi

if ! command -v bash >/dev/null 2>&1 || [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  die "bash >= 4 is required."
fi

if [ ! -f /etc/os-release ]; then
  die "Cannot detect OS (/etc/os-release missing) — this installer targets Debian/Ubuntu."
fi
# shellcheck source=/dev/null
. /etc/os-release
case "${ID:-}" in
  debian|ubuntu) : ;;
  *)
    die "Unsupported OS '${ID:-unknown}' — this installer targets Debian/Ubuntu only."
    ;;
esac

log "Installing prerequisites (git, curl, ca-certificates)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git ca-certificates curl >/dev/null

if [ -d "$INSTALL_DIR/.git" ]; then
  log "Existing checkout found at $INSTALL_DIR — updating..."
  if ! git -C "$INSTALL_DIR" fetch --quiet origin "$REPO_BRANCH" \
      || ! git -C "$INSTALL_DIR" reset --hard --quiet "origin/$REPO_BRANCH"; then
    backup="${INSTALL_DIR}.bak-$(date +%s)"
    log "Existing checkout looks broken — moving it to $backup and re-cloning."
    mv "$INSTALL_DIR" "$backup"
    git clone --quiet --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
  fi
elif [ -e "$INSTALL_DIR" ]; then
  backup="${INSTALL_DIR}.bak-$(date +%s)"
  log "$INSTALL_DIR exists but isn't a git checkout — moving it to $backup and cloning fresh."
  mv "$INSTALL_DIR" "$backup"
  git clone --quiet --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
else
  log "Cloning $REPO_URL into $INSTALL_DIR..."
  git clone --quiet --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR"/scripts/install/main.sh "$INSTALL_DIR"/scripts/manage.sh 2>/dev/null || true
find "$INSTALL_DIR/scripts" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

exec "$INSTALL_DIR/scripts/install/main.sh" "$@"

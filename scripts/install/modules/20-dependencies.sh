#!/usr/bin/env bash
# Installs everything else the installer and the app need: Docker, certbot,
# ufw, gum (from here on, UI switches from plain to gum), jq, openssl,
# dnsutils (for the DNS check module).

# Installed as a plain binary from GitHub releases, not via Charm's apt repo
# — `gpg --dearmor` on that repo's key needs a TTY in some environments
# (fails with "cannot open '/dev/tty'" under a non-interactive/piped
# install), and a broken/unsigned repo entry then poisons every later
# `apt-get update` in the same run, including the unrelated Docker install
# right after it. A single static binary has none of that surface.
module__install_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would download the latest gum release binary from GitHub"
    return 0
  fi

  local arch
  case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      ui::warn "No prebuilt gum binary for arch $(uname -m) — continuing with the plain-text UI."
      return 0
      ;;
  esac

  # Release assets are named e.g. gum_0.17.0_amd64.deb / gum_0.17.0_arm64.deb
  # — grabbing the .deb directly is simpler and more robust than the tar.gz
  # (no archive-layout guessing, and dpkg registers it properly).
  local asset_url
  asset_url="$(
    curl -fsSL https://api.github.com/repos/charmbracelet/gum/releases/latest \
      | grep -oE "\"browser_download_url\": *\"[^\"]*gum_[^\"]*_${arch}\.deb\"" \
      | head -1 \
      | sed -E 's/.*"(https[^"]+)"/\1/'
  )"
  if [ -z "$asset_url" ]; then
    ui::warn "Couldn't resolve the latest gum release — continuing with the plain-text UI."
    return 0
  fi

  local tmp_deb
  tmp_deb="$(mktemp --suffix=.deb)"
  if ! curl -fsSL "$asset_url" -o "$tmp_deb"; then
    ui::warn "Failed to download gum from $asset_url — continuing with the plain-text UI."
    rm -f "$tmp_deb"
    return 0
  fi
  dpkg -i "$tmp_deb" >/dev/null 2>&1
  rm -f "$tmp_deb"
}

module_dependencies() {
  ui::header "Installing dependencies"

  # curl/ca-certificates are normally already present by this point (install.sh's
  # bootstrap installs them before cloning) — but main.sh is also meant to be
  # runnable directly from an existing clone without going through install.sh,
  # so don't assume it; install them here too if missing.
  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would apt-get install: curl ca-certificates certbot ufw jq openssl dnsutils"
  else
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq curl ca-certificates certbot ufw jq openssl dnsutils >/dev/null
  fi

  module__install_gum
  ui::init # re-detect UI_MODE now that gum (should be) present

  docker::install

  ui::success "Dependencies installed."
}

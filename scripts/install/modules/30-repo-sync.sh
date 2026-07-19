#!/usr/bin/env bash
# The bootstrap (install.sh) already clones/updates the repo before handing
# off to main.sh, so this is a no-op during a fresh install — it exists as
# its own module so manage.sh's "update" action can call the same function
# standalone without re-running the whole install sequence.

module_repo_sync() {
  ui::header "Syncing repo"

  if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
    ui::info "[dry-run] would run: git -C $INSTALL_DIR fetch && git reset --hard origin/<branch>"
    return 0
  fi

  if [ ! -d "$INSTALL_DIR/.git" ]; then
    ui::warn "$INSTALL_DIR isn't a git checkout — skipping repo sync (was this installed a different way?)."
    return 0
  fi

  local branch
  branch="$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD)"
  git -C "$INSTALL_DIR" fetch --quiet origin "$branch"
  git -C "$INSTALL_DIR" reset --hard --quiet "origin/$branch"
  find "$INSTALL_DIR/scripts" -name '*.sh' -exec chmod +x {} +
  ui::success "Repo synced to latest $branch."
}

#!/usr/bin/env bash
# Optional N501 Verse installer.
#
# Requires Kotonoha 0.2.3 to be installed separately before it adds or
# updates the git-managed plugin and places the widget after tablet-mode.
# Run `bash install.sh` from the public repository root.
# Idempotent: fresh installs add the plugin, existing git checkouts
# update it, and a pre-existing non-git plugin directory is refused
# without deleting anything.
set -euo pipefail

PLUGIN_ID="n501.karaoke"
REPO_URL="https://github.com/Nombah501/n501-verse.git"
PYTHON="/usr/bin/python3"
KOTONOHA_VERSION="0.2.3"
KOTONOHA_RELEASE="https://github.com/locez/kotonoha/releases/tag/v0.2.3"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/n501.karaoke"

check_existing_plugin() {
  [[ -L "$PLUGIN_DIR" ]] && fail "$PLUGIN_DIR is a symlink; remove it or move it aside and retry"
  [[ -e "$PLUGIN_DIR" ]] || return 0
  [[ ! -L "$PLUGIN_DIR/.git" ]] || fail "$PLUGIN_DIR/.git is a symlink; move the checkout aside and retry"
  [[ -d "$PLUGIN_DIR/.git" ]] \
    || fail "$PLUGIN_DIR is not a standard git checkout; move it aside and retry"
  local inside_worktree checkout_root
  inside_worktree="$(git -C "$PLUGIN_DIR" rev-parse --is-inside-work-tree 2>/dev/null || true)"
  [[ "$inside_worktree" == "true" ]] \
    || fail "$PLUGIN_DIR is not a valid git checkout; move it aside and retry"
  checkout_root="$(git -C "$PLUGIN_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ "$checkout_root" == "$PLUGIN_DIR" ]] \
    || fail "$PLUGIN_DIR is not a repository root checkout; move it aside and retry"
  local origin
  origin="$(git -C "$PLUGIN_DIR" config --get remote.origin.url || true)"
  [[ "$origin" == "$REPO_URL" ]] \
    || fail "$PLUGIN_DIR has an unexpected git origin; expected the N501 Verse repository"
}


fail() {
  echo "install: $*" >&2
  exit 1
}

info() {
  echo "install: $*"
}

if [[ $# -gt 0 ]]; then
  fail "this installer takes no arguments"
fi

command -v omarchy >/dev/null 2>&1 || fail "omarchy command not found; run on Omarchy with omarchy installed"
command -v git >/dev/null 2>&1 || fail "git command not found; install git and retry"
[[ -x "$PYTHON" ]] || fail "/usr/bin/python3 not found; reinstall system python and retry"
check_existing_plugin

installed_version="$("$PYTHON" -c 'from importlib.metadata import version; print(version("kotonoha"))' 2>/dev/null)" \
  || fail "install Kotonoha $KOTONOHA_VERSION separately for $PYTHON before adding this plugin; see $KOTONOHA_RELEASE"
[[ "$installed_version" == "$KOTONOHA_VERSION" ]] \
  || fail "Kotonoha $KOTONOHA_VERSION required, found $installed_version; install the matching release separately: $KOTONOHA_RELEASE"
"$PYTHON" -c 'import kotonoha' >/dev/null 2>&1 \
  || fail "Kotonoha $KOTONOHA_VERSION is installed but cannot be imported by $PYTHON; repair that installation before adding this plugin"
info "Kotonoha $KOTONOHA_VERSION available"

if [[ ! -e "$PLUGIN_DIR" ]]; then
  info "adding $PLUGIN_ID from $REPO_URL"
  omarchy plugin add "$REPO_URL" --enable --yes \
    || fail "could not add $PLUGIN_ID from $REPO_URL"
else
  info "updating $PLUGIN_ID"
  omarchy plugin update "$PLUGIN_ID" --yes || fail "could not update $PLUGIN_ID"
  omarchy plugin enable "$PLUGIN_ID" || fail "could not enable $PLUGIN_ID"
fi

info "placing $PLUGIN_ID after tablet-mode"
omarchy bar put "$PLUGIN_ID" --after tablet-mode \
  || fail "could not put $PLUGIN_ID on the bar"
omarchy bar move "$PLUGIN_ID" --section left --after tablet-mode \
  || fail "could not place $PLUGIN_ID after tablet-mode"

info "done: $PLUGIN_ID installed after tablet-mode"

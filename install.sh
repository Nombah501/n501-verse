#!/usr/bin/env bash
# N501 Verse bootstrap installer.
#
# One explicit command installs the missing Kotonoha AUR dependency,
# installs or updates the git-managed plugin, and places the widget
# after tablet-mode. Run from anywhere:
#   bash plugins/n501.karaoke/install.sh
#
# Idempotent: fresh installs add the plugin, existing git checkouts
# update it, and a pre-existing non-git plugin directory is refused
# without deleting anything.
set -euo pipefail

PLUGIN_ID="n501.karaoke"
REPO_URL="https://github.com/Nombah501/n501-verse.git"
PYTHON="/usr/bin/python3"
AUR_PACKAGE="kotonoha-git"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/n501.karaoke"

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

if "$PYTHON" -c "import kotonoha" >/dev/null 2>&1; then
  info "kotonoha already importable; skipping AUR install"
else
  info "installing $AUR_PACKAGE"
  omarchy pkg aur add "$AUR_PACKAGE" || fail "could not install $AUR_PACKAGE; run 'omarchy pkg aur add $AUR_PACKAGE' manually and retry"
  "$PYTHON" -c "import kotonoha" >/dev/null 2>&1 || fail "kotonoha still not importable by /usr/bin/python3 after installing $AUR_PACKAGE; run 'omarchy pkg aur add $AUR_PACKAGE' manually and retry"
  info "kotonoha import OK"
fi

if [[ -L "$PLUGIN_DIR" ]]; then
  fail "$PLUGIN_DIR is a symlink; remove it or move it aside and retry"
elif [[ ! -e "$PLUGIN_DIR" ]]; then
  info "adding $PLUGIN_ID from $REPO_URL"
  omarchy plugin add "$REPO_URL" --enable --yes \
    || fail "could not add $PLUGIN_ID from $REPO_URL"
elif [[ -d "$PLUGIN_DIR/.git" ]]; then
  info "updating $PLUGIN_ID"
  omarchy plugin update "$PLUGIN_ID" --yes || fail "could not update $PLUGIN_ID"
  omarchy plugin enable "$PLUGIN_ID" || fail "could not enable $PLUGIN_ID"
else
  fail "$PLUGIN_DIR exists and is not a git checkout; move it aside and retry"
fi

info "placing $PLUGIN_ID after tablet-mode"
omarchy bar put "$PLUGIN_ID" --after tablet-mode \
  || fail "could not place $PLUGIN_ID after tablet-mode"

info "done: $PLUGIN_ID installed after tablet-mode"

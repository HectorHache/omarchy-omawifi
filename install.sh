#!/usr/bin/env bash
#
# Wi-Fi Anchor - local installer for the Omarchy shell.
#
# Copies this plugin into ~/.config/omarchy/plugins/, lets you choose which bar
# section it lives in (left, center or right - the same choice Omarchy offers
# when you `omarchy plugin add` a published plugin), enables it there and
# reloads the shell.
#
# For a published copy you do not need this script at all:
#   omarchy plugin add https://github.com/HectorHache/omarchy-omawifi --enable
# already asks you the same left/center/right question (default: right).
#
# Usage:
#   ./install.sh                 # ask for the section (default: right)
#   ./install.sh right|center|left
#   SECTION=center ./install.sh  # non-interactive
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export OMARCHY_PATH XDG_RUNTIME_DIR

command -v omarchy >/dev/null 2>&1 || {
  echo "install.sh: this needs Omarchy (the 'omarchy' command) on PATH." >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || { echo "install.sh: 'jq' is required." >&2; exit 1; }

ID="$(jq -r '.id' "$SRC/manifest.json")"
DEFAULT_SECTION="$(jq -r '.barWidget.defaultSection // "right"' "$SRC/manifest.json")"

# --- choose the bar section ------------------------------------------------
section="${1:-${SECTION:-}}"
if [[ -z $section ]]; then
  if command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
    section="$(printf '%s\n' left center right |
      gum choose --header="Place Wi-Fi Anchor in which bar section?" \
        --selected "$DEFAULT_SECTION")" || section="$DEFAULT_SECTION"
  elif [[ -t 0 ]]; then
    read -rp "Bar section - left/center/right [$DEFAULT_SECTION]: " section
  fi
fi
section="${section:-$DEFAULT_SECTION}"
[[ $section =~ ^(left|center|right)$ ]] ||
  { echo "install.sh: section must be left, center or right (got '$section')." >&2; exit 1; }

# --- validate the source folder --------------------------------------------
echo "Validating the plugin..."
omarchy plugin validate "$SRC"

# --- install real files (no symlinks; leave dev-only bits behind) ----------
DEST="$HOME/.config/omarchy/plugins/$ID"
echo "Installing to $DEST"
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -r "$SRC" "$DEST"
rm -rf "$DEST/tests" "$DEST/.git" "$DEST/install.sh"

# --- enable it in the chosen section, then reload the shell ----------------
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin enable "$ID" --section "$section"

# Quickshell does not hot-reload QML; the wrapper respawns it after a kill.
pkill -x quickshell 2>/dev/null || true

echo "Done. Wi-Fi Anchor is enabled in the '$section' section."
echo "The bar reloads in a few seconds. Move it later with:"
echo "  omarchy plugin enable $ID --section left|center|right"

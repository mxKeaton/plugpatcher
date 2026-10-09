#!/usr/bin/env bash
#
# Install PlugPatcher: the CLI and the Quickshell manager plugin.
# Everything is user-space; nothing in /usr/share/omarchy is touched.
#
# The AI agent skill lives in this repo at skills/plugpatcher/SKILL.md;
# copy it into your agent's skills directory yourself (see README).
#
# Usage: ./install.sh [--enable]
#   --enable   also enable the PlugPatcher bar widget

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
ENABLE=0
[[ "${1:-}" == "--enable" ]] && ENABLE=1

command -v jq >/dev/null 2>&1 || { echo "install.sh: jq is required" >&2; exit 1; }
PLUGIN_ID="$(jq -r '.id' "$REPO/plugin/manifest.json")"
[[ -n "$PLUGIN_ID" && "$PLUGIN_ID" != null ]] || { echo "install.sh: cannot read the plugin id" >&2; exit 1; }

mkdir -p "$BIN_DIR" "$PLUGINS_DIR"

install -m755 "$REPO/bin/plugpatcher" "$BIN_DIR/plugpatcher"
rm -rf "$PLUGINS_DIR/$PLUGIN_ID"
cp -a "$REPO/plugin" "$PLUGINS_DIR/$PLUGIN_ID"

omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

echo "Installed plugpatcher to $BIN_DIR/plugpatcher"
echo "Installed manager plugin to $PLUGINS_DIR/$PLUGIN_ID"

if (( ENABLE )); then
  omarchy plugin enable "$PLUGIN_ID" >/dev/null && echo "Enabled the PlugPatcher bar widget"
else
  echo "Enable the bar widget with: omarchy plugin enable $PLUGIN_ID"
fi

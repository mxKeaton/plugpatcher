#!/usr/bin/env bash
#
# Install PlugPatcher locally: the CLI on PATH (convenience) and the Quickshell
# manager plugin. The plugin itself is self-contained — it runs the CLI that
# ships inside it (bin/plugpatcher) — so `omarchy plugin add <url>` works without
# this script. Everything is user-space; nothing in /usr/share/omarchy is touched.
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
PLUGIN_ID="$(jq -r '.id' "$REPO/manifest.json")"
[[ -n "$PLUGIN_ID" && "$PLUGIN_ID" != null ]] || { echo "install.sh: cannot read the plugin id" >&2; exit 1; }

mkdir -p "$BIN_DIR" "$PLUGINS_DIR"

# Convenience copy on PATH; the panel uses the bundled one regardless.
install -m755 "$REPO/bin/plugpatcher" "$BIN_DIR/plugpatcher"

# Lay down the plugin (manifest + entry points + bundled CLI), like a clone of
# the repo would.
target="$PLUGINS_DIR/$PLUGIN_ID"
rm -rf "$target"
mkdir -p "$target/bin"
for f in manifest.json LICENSE README.md; do
  [[ -e "$REPO/$f" ]] && cp -a "$REPO/$f" "$target/$f"
done
cp -a "$REPO"/Panel.qml "$REPO"/PlugScrollBar.qml "$target/" 2>/dev/null || true
cp -a "$REPO/bin/plugpatcher" "$target/bin/plugpatcher"

omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

echo "Installed plugpatcher to $BIN_DIR/plugpatcher"
echo "Installed manager plugin to $target"

if (( ENABLE )); then
  omarchy plugin enable "$PLUGIN_ID" >/dev/null && echo "Enabled the PlugPatcher bar widget"
else
  echo "Enable the bar widget with: omarchy plugin enable $PLUGIN_ID"
fi

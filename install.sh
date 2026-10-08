#!/usr/bin/env bash
#
# Install PlugPatcher: the CLI, the Quickshell manager plugin, and the AI skill.
# Everything is user-space; nothing in /usr/share/omarchy is touched.
#
# Usage: ./install.sh [--enable]
#   --enable   also enable the "plugpatcher" bar widget

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
SKILL_DIR="$HOME/.pi/agent/skills/plugpatcher"
ENABLE=0
[[ "${1:-}" == "--enable" ]] && ENABLE=1

mkdir -p "$BIN_DIR" "$PLUGINS_DIR" "$SKILL_DIR"

install -m755 "$REPO/bin/plugpatcher" "$BIN_DIR/plugpatcher"
rm -rf "$PLUGINS_DIR/plugpatcher"
cp -a "$REPO/plugin" "$PLUGINS_DIR/plugpatcher"
install -m644 "$REPO/skills/plugpatcher/SKILL.md" "$SKILL_DIR/SKILL.md"

omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

echo "Installed plugpatcher to $BIN_DIR/plugpatcher"
echo "Installed manager plugin to $PLUGINS_DIR/plugpatcher"
echo "Installed skill to $SKILL_DIR/SKILL.md"

if (( ENABLE )); then
  omarchy plugin enable plugpatcher >/dev/null && echo "Enabled the PlugPatcher bar widget"
else
  echo "Enable the bar widget with: omarchy plugin enable plugpatcher"
fi

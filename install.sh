#!/usr/bin/env bash
#
# Install PlugPatcher: the CLI and the Quickshell manager plugin.
# Everything is user-space; nothing in /usr/share/omarchy is touched.
#
# The AI agent skill lives in this repo at skills/plugpatcher/SKILL.md;
# copy it into your agent's skills directory yourself (see README).
#
# Usage: ./install.sh [--enable]
#   --enable   also enable the "plugpatcher" bar widget

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
ENABLE=0
[[ "${1:-}" == "--enable" ]] && ENABLE=1

mkdir -p "$BIN_DIR" "$PLUGINS_DIR"

install -m755 "$REPO/bin/plugpatcher" "$BIN_DIR/plugpatcher"
rm -rf "$PLUGINS_DIR/plugpatcher"
cp -a "$REPO/plugin" "$PLUGINS_DIR/plugpatcher"

omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

echo "Installed plugpatcher to $BIN_DIR/plugpatcher"
echo "Installed manager plugin to $PLUGINS_DIR/plugpatcher"

if (( ENABLE )); then
  omarchy plugin enable plugpatcher >/dev/null && echo "Enabled the PlugPatcher bar widget"
else
  echo "Enable the bar widget with: omarchy plugin enable plugpatcher"
fi

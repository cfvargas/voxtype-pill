#!/usr/bin/env bash
# Remove the "pill" OSD style and restore the config install.sh backed up.
#
#   ./uninstall.sh
set -euo pipefail

info() { printf '\033[36m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml"
STYLE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/osd/pill"
BACKUP="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml.voxtype-pill.bak"

if [ -d "$STYLE_DIR" ]; then
  rm -rf "$STYLE_DIR"
  info "removed $STYLE_DIR"
fi

if [ -f "$BACKUP" ]; then
  cp "$BACKUP" "$CONFIG"
  rm -f "$BACKUP"
  info "restored your config from the backup taken at install time"
else
  warn "no install-time backup found; leaving config as is."
  warn "to revert manually: voxtype config unset osd.style (and osd.frontend, etc.)"
fi

if systemctl --user list-unit-files voxtype.service >/dev/null 2>&1; then
  info "restarting the voxtype daemon…"
  systemctl --user restart voxtype.service
else
  warn "voxtype.service not found under systemd --user. Restart the daemon yourself."
fi

info "done."

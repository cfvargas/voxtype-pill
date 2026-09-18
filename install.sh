#!/usr/bin/env bash
# Install the "pill" OSD style for voxtype.
#
# Copies the style into voxtype's style directory, points the [osd] config at
# it, and restarts the daemon. Your current config is backed up first, so the
# uninstall can put it back exactly.
#
#   ./install.sh
#
# Scope: visual only. It never touches audio, transcription, hotkeys, or your
# chosen engine. It sets keys under [osd] and nothing else.
set -euo pipefail

info() { printf '\033[36m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml"
STYLE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/osd/pill"
BACKUP="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml.voxtype-pill.bak"

command -v voxtype >/dev/null || die "voxtype is not installed. See https://voxtype.io"
command -v qs >/dev/null 2>&1 || warn "quickshell ('qs') not found. The pill needs the quickshell frontend; install quickshell first."

# Back up the config once, before the first change, so uninstall is exact.
if [ -f "$CONFIG" ] && [ ! -f "$BACKUP" ]; then
  cp "$CONFIG" "$BACKUP"
  info "backed up config to $(basename "$BACKUP")"
fi

# Copy the style package into voxtype's style directory.
mkdir -p "$(dirname "$STYLE_DIR")"
rm -rf "$STYLE_DIR"
cp -r "$SRC_DIR/pill" "$STYLE_DIR"
info "installed style to $STYLE_DIR"

# Point [osd] at the pill. `voxtype config set` type-checks each value and
# preserves comments and unrelated settings. voxtype forwards position,
# margin_px, top_margin, palette and layout to custom styles in its style JSON.
# It does NOT forward waveform_gain, so the pill reads that key from config.toml
# directly; setting it here (and later with `voxtype config set`) tunes the
# pill's sensitivity. window_secs, peak_decay and opacity apply only to the
# built-in renderer, so they are left alone.
info "configuring [osd]…"
voxtype config set osd.enabled               true
voxtype config set osd.frontend              quickshell
voxtype config set osd.style                 pill
voxtype config set osd.palette               omarchy
voxtype config set osd.layout                custom
voxtype config set osd.position              bottom-center
voxtype config set osd.top_margin            0.90
voxtype config set osd.margin_px             24
voxtype config set osd.waveform_gain         3.0

# The frontend change needs a daemon restart (it reloads the model, so this
# takes a few seconds).
if systemctl --user list-unit-files voxtype.service >/dev/null 2>&1; then
  info "restarting the voxtype daemon…"
  systemctl --user restart voxtype.service
else
  warn "voxtype.service not found under systemd --user. Restart the daemon yourself for the change to take effect."
fi

info "done. Hold your push-to-talk key and speak to see the pill."
info "If the bars saturate or barely move, tune it: voxtype config set osd.waveform_gain <n> (see README)."

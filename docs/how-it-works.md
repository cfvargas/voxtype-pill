# How voxtype's OSD works

Notes from reverse-engineering a local install (voxtype-bin 1.0.1 on Omarchy).
Everything here is visual. None of it touches audio, transcription, or the
daemon. If you want to build your own voxtype style, start here.

## Three findings that govern everything

**1. The default `gtk4` frontend ignores custom visuals.** It accepts geometry
keys such as `position` and `margin_px`, but it draws its own fixed design and
discards custom layers. Any real redesign needs `osd.frontend = "quickshell"`.

**2. `position` does not set the vertical placement. `top_margin` does.** For
the centered anchors (`top-center`, `bottom-center`) the vertical position is
`screen_height * top_margin`. The default is `0.85`, which is near the bottom,
so `position = "top-center"` alone still leaves the widget low. Set
`top_margin` to place it. Corner anchors use `margin_px` directly instead.

**3. Sizes are logical pixels, not physical.** On a monitor at scale 1.6, a
width of 460 logical pixels is 736 physical pixels in a screenshot. `hyprctl
layers` and `grim -g` speak logical pixels; captures come out physical.

## The pieces

| Piece | Path | What it is |
|---|---|---|
| Daemon | `voxtype daemon` | Launches the OSD and publishes audio frames |
| gtk4 OSD | `/usr/lib/voxtype/voxtype-osd-gtk4` | The default. Fixed design. |
| quickshell OSD | `/usr/lib/voxtype/voxtype-osd-quickshell` | Loads `qs`. The one you can restyle. |
| System QML | `/usr/share/voxtype/quickshell/` | `OsdSurface.qml`, `StyleLoader.qml`, and shared modules |
| Audio socket | `$XDG_RUNTIME_DIR/voxtype/audio.sock` | Live frames (peak, rms, vad) |
| State | `$XDG_RUNTIME_DIR/voxtype/state` | `idle` / `recording` / `transcribing` |
| Config | `~/.config/voxtype/config.toml` | The `[osd]` section |

The OSD binaries accept `--config <file>`, so you can preview a design without
touching your real config.

## Style packages

A style is a directory with a `voxtype-osd.toml` manifest. The launcher reads
that file to recognize the directory as a package. Its `qml_entry` names the
QML that replaces the built-in card.

```toml
version       = "1.0.0"
description   = "..."
compatibility = "1.0"
qml_entry     = "Pill.qml"
palette       = "omarchy"
layout        = "custom"

[visual]
layers = []
```

Select it with `osd.style = "<name>"`, or preview it directly:

```bash
voxtype-osd-quickshell --style /path/to/pill --config <recipe>
```

Packages install into `~/.config/voxtype/osd/` or
`~/.local/share/voxtype/osd/`.

## The `qml_entry` contract

`OsdSurface.qml` loads your QML in a `Loader` anchored to the whole screen, so
your QML positions and draws the widget itself. The loader injects these, if
you declare them as properties:

| Property | Contents |
|---|---|
| `daemonState` | `idle` / `recording` / `streaming` / `transcribing` |
| `audio` | AudioBridge; emits `frameReceived(peak, rms, vad, tsMs)` |
| `theme` | StyleLoader: `.config` (resolved JSON) and `.color(role, fallback)` |
| `recipe` | `config.visual` (the layers, if you want to interpret them) |
| `assetRoot` | Base path for the package's assets |

### Not every `[osd]` key reaches a custom style

`theme.config` is the resolved style JSON voxtype writes to
`$XDG_RUNTIME_DIR/voxtype/quickshell-style.json`. It carries only a subset of
the `[osd]` keys: `style`, `palette`, `layout`, `position`, `margin_px`,
`top_margin`, the resolved `colors`, `frame`, and `visual`. It does **not**
include `waveform_gain`, `waveform_window_secs`, `peak_decay_db_per_sec`, or
`opacity`. Those apply to voxtype's built-in renderer.

A custom style that wants one of those keys has to read the config file itself.
This pill does exactly that for `waveform_gain`: it `cat`s
`~/.config/voxtype/config.toml`, parses the `osd.waveform_gain` line, and
re-reads it on each appearance, the same pattern it uses for the theme. That is
why `voxtype config set osd.waveform_gain <n>` tunes the pill and takes effect on
the next dictation, even though the key never arrives in the style JSON.

## Why this design reads the theme file directly

`Pill.qml` reads the Omarchy theme's `colors.toml` instead of only the roles
voxtype exposes. The exposed roles are few, and some are fixed (the recording
role is always a set red even when the theme's red differs). Every Omarchy
theme ships `red`, `accent`, `magenta`, and `dark_background`, so mapping those
works across all of them.

Live reload is harder than it looks. `omarchy-theme-set` does `rm -rf` plus
`mv` on `current/theme`, so the file the widget was watching disappears and a
new one takes its place under the same name. A QML `FileView` with
`watchChanges`, `reload()`, or a re-opened path keeps pointing at the file that
no longer exists. The reliable fix is to read the file with `cat` through a
`Process` each time the widget appears. A fresh process always reads the
current contents of the path, whatever the inode.

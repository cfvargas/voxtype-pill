// voxtype OSD redesign: a pill with a recording dot and a thin-bar waveform.
//
// Contract with OsdSurface.qml: its Loader fills the whole screen and injects
// the properties below, so positioning is our job. The built-in layer types do
// not fit here. `bars` caps at 28 bars with a vertical gradient, and this
// design wants ~72 thin bars running blue to magenta.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Injected by OsdSurface.
    property string daemonState: "idle"
    property var audio: null
    property var theme: null      // VT.StyleLoader

    // Design. Measurements taken from the mockup (a 447x60 pill on 1280).
    readonly property int  pillWidth:      253         // recording width (two-thirds of 380)
    readonly property int  pillWidthMin:   110         // transcribing width, fit to the mini wave
    readonly property int  pillHeight:      50
    readonly property real pillRadius:      pillHeight / 2

    // The pill shrinks around the dots during transcription. This width
    // interpolates on the recording<->transcribing crossfade, which is already
    // smoothed, so the shrink inherits that curve.
    readonly property real curPillWidth:
        pillWidth + (pillWidthMin - pillWidth) * _transProgress

    // Colors follow the active Omarchy theme. The roles the launcher exposes
    // (theme.color) are few and some are fixed (recording is always #F2594D,
    // not the theme's red), so we read the theme's colors.toml directly (see the
    // theme reader below). Every color falls back to the mockup value.
    property var themeColors: ({})

    function _tc(key, fallback) {
        const v = themeColors[key];
        return (typeof v === "string" && v.length === 7) ? v : fallback;
    }

    // Four theme keys: the background, the red, and two for the bars. The border
    // spends no key; it is derived by lightening the background.
    readonly property string bgHex:     _tc("dark_background", _tc("background", "#0B121A"))
    readonly property color  pillColor:  _withAlpha(bgHex, 0.99)
    readonly property color  pillBorder: _mix(bgHex, "#FFFFFF", 0.14)
    readonly property color  dotColor:   _tc("red", "#E73B36")

    // Bars run from the theme's identity color (accent, blue in almost every
    // theme) to magenta. Two colors keep the mockup's gesture: the first holds
    // for a third of the run before it turns.
    readonly property string gradA: _tc("accent", _tc("blue", "#6683D4"))
    readonly property string gradB: _tc("magenta", "#9A5CD5")
    readonly property var gradientStops: [
        { at: 0.00, color: gradA },
        { at: 0.35, color: gradA },
        { at: 1.00, color: gradB }
    ]

    // "#RRGGBB" + alpha 0..1 -> "#AARRGGBB", the form QML and Canvas accept.
    function _withAlpha(hex, alpha) {
        const a = Math.round(_clamp(alpha, 0, 1) * 255);
        return "#" + (a < 16 ? "0" : "") + a.toString(16) + String(hex).slice(1);
    }

    function _mix(a, b, t) {
        const pa = _rgb(a), pb = _rgb(b);
        const c = [0, 1, 2].map(i => Math.round(pa[i] + (pb[i] - pa[i]) * t));
        return "#" + c.map(v => (v < 16 ? "0" : "") + v.toString(16)).join("");
    }

    function _rgb(hex) {
        const h = String(hex).slice(1);
        return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
    }

    // "transcribing" state: the same wave, condensed. There is no audio while
    // the model works, so a synthetic pulse sweeps the bubble left to right, as
    // if the audio you recorded still flows through it while it turns into text.
    // It shares bars and gradient with recording, so the crossfade between the
    // two states never switches visual language.
    readonly property int  pulsePad:      23            // edge -> first bar
    readonly property real pulseMaxAmp:   12            // a touch calmer than recording
    readonly property real pulseSpeed:     1.15         // sweeps per second (~1.5 s)
    readonly property real pulseFront:     0.08         // leading-edge sigma (sharp)
    readonly property real pulseTail:      0.20         // trailing-edge sigma (long)
    readonly property real pulseBreath:    0.06         // background beat, never flat

    readonly property int  dotDiameter:  16
    readonly property int  padLeft:      20             // edge -> dot
    readonly property int  gapAfterDot:  18             // dot -> bars
    readonly property int  padRight:     16

    readonly property real barWidth:      3
    readonly property real barPitch:      5             // center to center
    readonly property real barMinHeight:  2.5           // silence = tiny dots
    readonly property real barMaxAmp:     14            // peak, from the center

    // Smooth the signal before drawing. The daemon's raw peak jumps fast
    // (100 Hz) and looks nervous; a fast attack and slow release let the bars
    // rise with energy and settle gently instead of snapping.
    readonly property real attackPerFrame:  0.55        // rise (0..1 per frame)
    readonly property real releasePerFrame: 0.07        // fall, slower

    // Visual gain applied to each peak before drawing. Sourced from
    // osd.waveform_gain in config.toml (see the config reader below), so
    // `voxtype config set osd.waveform_gain <n>` and the config TUI tune it,
    // applied on the next dictation with no restart. voxtype does not forward
    // this key in the style JSON it hands custom QML, so the widget reads
    // config.toml directly. Stays at the default until the file is read.
    property real gain: 3.0

    // Position comes from the config, like the built-in surface. For the
    // centered anchors the vertical is set by `top_margin` (a fraction of
    // monitor height), not the top/bottom word.
    function _cfg() { return theme && theme.config ? theme.config : null; }

    function _cfgNum(key, fallback) {
        const c = _cfg();
        return c && c[key] !== undefined && c[key] !== null ? Number(c[key]) : fallback;
    }

    function _cfgStr(key, fallback) {
        const c = _cfg();
        return c && c[key] ? String(c[key]) : fallback;
    }

    readonly property string position:  _cfgStr("position", "top-center")
    readonly property int    marginPx:  Math.max(0, _cfgNum("margin_px", 24))
    readonly property real   topMargin: Math.max(0, Math.min(1, _cfgNum("top_margin", 0.04)))

    function _pillX() {
        if (position.indexOf("left")  >= 0) return marginPx;
        if (position.indexOf("right") >= 0) return Math.max(marginPx, root.width - pillWidth - marginPx);
        return Math.max(marginPx, (root.width - pillWidth) / 2);
    }

    function _pillY() {
        if (position === "top-left"    || position === "top-right")    return marginPx;
        if (position === "bottom-left" || position === "bottom-right")
            return Math.max(marginPx, root.height - pillHeight - marginPx);
        return Math.max(marginPx,
               Math.min(root.height - pillHeight - marginPx, root.height * topMargin));
    }

    // Audio signal: a history of peaks, most recent on the right.
    readonly property int barCount:
        Math.max(1, Math.floor((pillWidth - padLeft - dotDiameter - gapAfterDot - padRight) / barPitch))

    property var levels: []          // smoothed level per bar, 0..1
    property real _lastTick: Date.now()
    property real _level: 0.0         // level with attack/release, the pushed value

    // Crossfade progress bars<->dots (0 = recording, 1 = transcribing). Animated
    // so releasing the key fades one view into the other.
    property real _transProgress: 0.0

    // Demo mode (VOXTYPE_PILL_DEMO=1): synthesizes a voice-like envelope so the
    // design can be reviewed with real amplitude without a mic. Drawing only; it
    // never touches audio capture.
    readonly property bool demo: Quickshell.env("VOXTYPE_PILL_DEMO") === "1"
    property real _demoPhase: 0

    // Animation phase, advances whenever the widget is visible.
    property real _phase: 0

    // State override for captures (VOXTYPE_PILL_STATE=transcribing). Drawing
    // only; the real daemon state is untouched.
    readonly property string stateOverride: Quickshell.env("VOXTYPE_PILL_STATE") || ""
    readonly property string drawState: stateOverride.length > 0 ? stateOverride : daemonState

    readonly property bool transcribing: drawState === "transcribing"

    readonly property int pulseBarCount:
        Math.max(3, Math.floor((pillWidthMin - 2 * pulsePad) / barPitch))

    // The pulse resets its phase to zero when transcription begins, so the first
    // sweep enters from the left exactly as the pill collapses. The recording
    // energy appears to pour into the bubble.
    property real _pulsePhase: 0.0
    onTranscribingChanged: if (transcribing) _pulsePhase = 0.0

    // Level 0..1 of the bar at position t (0 left, 1 right) for the traveling
    // pulse. Sharp leading edge, long tail, so it reads as flowing energy, not a
    // bouncing ball. A second, dimmer pulse at half distance and a faint
    // background beat keep the bubble from going flat between sweeps.
    function _pulseAt(t, pos) {
        const d = t - pos;
        const sigma = d > 0 ? pulseFront : pulseTail;
        return Math.exp(-(d * d) / (2 * sigma * sigma));
    }

    function _pulseLevel(t) {
        const travel = 1.9;
        const base = ((_pulsePhase * pulseSpeed) % travel + travel) % travel;
        const pos1 = -0.25 + base;
        const pos2 = -0.25 + ((base + travel / 2) % travel);
        const pulse = _pulseAt(t, pos1) + 0.45 * _pulseAt(t, pos2);
        const breath = pulseBreath * (0.5 + 0.5 * Math.sin(_phase * 2.0 + t * 4.0));
        return _clamp(pulse + breath, 0, 1);
    }

    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    // Asymmetric temporal smoothing: rises fast, falls slow. VU-meter inertia
    // instead of sample-to-sample flicker.
    function _approach(current, target, stiffness, dt) {
        return current + (target - current) * (1 - Math.exp(-Math.max(0.01, stiffness) * dt));
    }

    Component.onCompleted: { _resetLevels(); _reloadTheme(); _reloadConfig(); }

    function _resetLevels() {
        const next = [];
        for (let i = 0; i < barCount; i++) next.push(0.0);
        levels = next;
    }

    onBarCountChanged: _resetLevels()

    onDaemonStateChanged: {
        if (daemonState === "idle") {
            _resetLevels();
            _level = 0.0;
            _transProgress = 0.0;
        } else if (daemonState === "recording" || daemonState === "streaming") {
            // The widget only shows while recording, so re-reading the theme and
            // the config on each appearance keeps colors and gain fresh without
            // polling. watchChanges misses the theme switch (see the readers).
            _reloadTheme();
            _reloadConfig();
        }
    }

    // Each daemon frame shifts the history one bar left. The value pushed is the
    // attack/release-smoothed level, not the raw peak, so the right edge rises
    // and falls smoothly.
    Connections {
        target: root.audio
        enabled: root.audio !== null
        ignoreUnknownSignals: true
        function onFrameReceived(peak, rms, vad, tsMs) {
            const target = root._clamp(peak * root.gain, 0, 1);
            const k = target > root._level ? root.attackPerFrame : root.releasePerFrame;
            root._level += (target - root._level) * k;

            const next = root.levels.slice();
            next.push(root._level);
            while (next.length > root.barCount) next.shift();
            while (next.length < root.barCount) next.unshift(0.0);
            root.levels = next;
        }
    }

    // Synthetic envelope: syllables over a slow carrier, louder toward the
    // right, like the mockup's trace.
    function _stepDemo(dt) {
        _demoPhase += dt * 2.2;
        const next = [];
        for (let i = 0; i < barCount; i++) {
            const t = barCount <= 1 ? 1 : i / (barCount - 1);
            const syllable = Math.pow(Math.max(0, Math.sin(t * 22 + _demoPhase)), 3);
            const breath   = 0.5 + 0.5 * Math.sin(t * 5.5 + _demoPhase * 0.6);
            const ramp     = 0.18 + 0.82 * t;
            next.push(_clamp(syllable * breath * ramp, 0, 1));
        }
        levels = next;
    }

    Timer {
        interval: root.daemonState === "recording" ? 16 : 33
        repeat: true
        running: root.demo || (root.daemonState !== "idle" && root.daemonState !== "")
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            const dt = Math.min(0.05, Math.max(0.001, (now - root._lastTick) / 1000));
            root._lastTick = now;
            root._phase += dt;
            root._pulsePhase += dt;
            root._transProgress = root._approach(root._transProgress,
                                                 root.transcribing ? 1.0 : 0.0, 7.0, dt);
            if (root.demo && !root.transcribing) root._stepDemo(dt);
            canvas.requestPaint();
        }
    }

    // Omarchy theme: the active theme's colors.toml. The modern state lives in
    // ~/.local/state; the legacy path in ~/.config.
    readonly property string _home: Quickshell.env("HOME") || ""
    // VOXTYPE_PILL_THEME_FILE forces the colors.toml path for isolated tests;
    // empty means use Omarchy's real paths.
    readonly property string _themeOverride: Quickshell.env("VOXTYPE_PILL_THEME_FILE") || ""

    // Minimal parser: only `key = "#rrggbb"` lines, which is all the file has.
    function _parseTheme(text) {
        const out = {};
        const re = /^\s*([A-Za-z_]+)\s*=\s*"(#[0-9A-Fa-f]{6})"/;
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = re.exec(lines[i]);
            if (m) out[m[1]] = m[2].toUpperCase();
        }
        if (Object.keys(out).length > 0) {   // don't overwrite with empty if cat fails
            themeColors = out;
            canvas.requestPaint();
        }
    }

    // Re-read the theme with `cat`. FileView does not work here: omarchy-theme-set
    // does rm+mv on current/theme, so the view stays bound to the old, deleted
    // inode, and neither watchChanges nor reload()/path-flip re-read reliably. A
    // fresh `cat` always reads the current contents of the path, whatever the
    // inode. Tries .local/state, falls back to .config (or the forced test path).
    function _reloadTheme() {
        themeReader.running = false;
        themeReader.running = true;
    }

    Process {
        id: themeReader
        running: false
        command: root._themeOverride.length > 0
            ? ["cat", root._themeOverride]
            : ["sh", "-c",
               "cat '" + root._home + "/.local/state/omarchy/current/theme/colors.toml' 2>/dev/null || " +
               "cat '" + root._home + "/.config/omarchy/current/theme/colors.toml' 2>/dev/null"]
        stdout: StdioCollector {
            id: themeOut
            onStreamFinished: root._parseTheme(themeOut.text)
        }
    }

    // Reinforcement: theme.name is small and theme-set rewrites it on every
    // change. If the compositor propagates the event, the widget recolors
    // without waiting for the next recording. The watcher may not fire after
    // rm+mv, so onDaemonStateChanged (every appearance) is the reliable path.
    FileView {
        id: themeNameFile
        path: root._home + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onFileChanged: root._reloadTheme()
    }

    // Waveform gain, read from osd.waveform_gain in config.toml. voxtype omits
    // this key from the style JSON it passes to custom QML, so the widget reads
    // the config file directly, like it reads the theme. Re-read on each
    // appearance, so `voxtype config set osd.waveform_gain <n>` (or the config
    // TUI) applies on the next dictation with no restart. Absent key keeps the
    // default.
    readonly property string _configPath:
        (Quickshell.env("XDG_CONFIG_HOME") || (_home + "/.config")) + "/voxtype/config.toml"

    function _reloadConfig() {
        configReader.running = false;
        configReader.running = true;
    }

    Process {
        id: configReader
        running: false
        command: ["sh", "-c", "cat '" + root._configPath + "' 2>/dev/null"]
        stdout: StdioCollector {
            id: configOut
            onStreamFinished: root._parseConfig(configOut.text)
        }
    }

    // Only the osd.waveform_gain line is needed, and it is unique in the file.
    function _parseConfig(text) {
        const m = /(^|\n)[ \t]*waveform_gain[ \t]*=[ \t]*([0-9]+(?:\.[0-9]+)?)/.exec(String(text || ""));
        if (m) gain = Number(m[2]);
    }

    Canvas {
        id: canvas
        readonly property int pad: 24   // glow room around the pill, per side

        x: root._pillX() - pad
        y: root._pillY() - pad
        width:  root.pillWidth  + 2 * pad
        height: root.pillHeight + 2 * pad
        antialiasing: true

        readonly property real ox: pad   // pill origin within the canvas
        readonly property real oy: pad

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.translate(ox, oy);

            // The pill shrinks toward the canvas center; its content is clipped
            // to the edge, so the bars slip behind the border as it narrows
            // instead of floating outside.
            const w    = root.curPillWidth;
            const left = (root.pillWidth - w) / 2;

            _paintPillBg(ctx, left, w);

            ctx.save();
            _pillPath(ctx, left, w);
            ctx.clip();

            const p = root._transProgress;
            if (p < 0.999) {
                _paintDot(ctx, left, 1 - p);
                _paintBars(ctx, left, 1 - p);
            }
            if (p > 0.001) {
                _paintPulse(ctx, left, w, p);
            }
            ctx.restore();

            _paintPillBorder(ctx, left, w);

            ctx.restore();
        }

        function _roundedRect(ctx, x, y, w, h, r) {
            const rr = Math.min(r, w / 2, h / 2);
            ctx.beginPath();
            ctx.moveTo(x + rr, y);
            ctx.lineTo(x + w - rr, y);
            ctx.arcTo(x + w, y, x + w, y + rr, rr);
            ctx.lineTo(x + w, y + h - rr);
            ctx.arcTo(x + w, y + h, x + w - rr, y + h, rr);
            ctx.lineTo(x + rr, y + h);
            ctx.arcTo(x, y + h, x, y + h - rr, rr);
            ctx.lineTo(x, y + rr);
            ctx.arcTo(x, y, x + rr, y, rr);
            ctx.closePath();
        }

        // Horizontal gradient across [x0, x1], set as the current fill. The
        // built-in `bars` layer only does vertical, which is why this is custom.
        function _setGradient(ctx, x0, x1) {
            const grad = ctx.createLinearGradient(x0, 0, x1, 0);
            for (let s = 0; s < root.gradientStops.length; s++) {
                grad.addColorStop(root.gradientStops[s].at, root.gradientStops[s].color);
            }
            ctx.fillStyle = grad;
        }

        // A bar of half-height `amp` mirrored about cy, with rounded caps.
        function _bar(ctx, x, cy, amp) {
            _roundedRect(ctx, x, cy - amp, root.barWidth, amp * 2, root.barWidth / 2);
            ctx.fill();
        }

        function _pillPath(ctx, left, w) {
            _roundedRect(ctx, left, 0, w, root.pillHeight, root.pillRadius);
        }

        function _paintPillBg(ctx, left, w) {
            ctx.fillStyle = root.pillColor;
            _pillPath(ctx, left, w);
            ctx.fill();
        }

        function _paintPillBorder(ctx, left, w) {
            ctx.strokeStyle = root.pillBorder;
            ctx.lineWidth = 1;
            _roundedRect(ctx, left + 0.5, 0.5, w - 1, root.pillHeight - 1, root.pillRadius);
            ctx.stroke();
        }

        function _paintDot(ctx, left, alpha) {
            const r  = root.dotDiameter / 2;
            const cx = left + root.padLeft + r;
            const cy = root.pillHeight / 2;
            ctx.globalAlpha = alpha;
            ctx.fillStyle = root.dotColor;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1.0;
        }

        // Transcription mini wave: the same bars and gradient as recording,
        // centered in the bubble, driven by the traveling pulse. `alpha` fades it
        // in with the recording view.
        function _paintPulse(ctx, left, w, alpha) {
            const n    = root.pulseBarCount;
            const span = (n - 1) * root.barPitch + root.barWidth;
            const x0   = left + (w - span) / 2;
            const cy   = root.pillHeight / 2;

            _setGradient(ctx, x0, x0 + span);
            ctx.globalAlpha = alpha;

            for (let i = 0; i < n; i++) {
                const t     = n <= 1 ? 0.5 : i / (n - 1);
                const level = root._pulseLevel(t);
                const amp   = root.barMinHeight / 2 + level * root.pulseMaxAmp;
                const x     = x0 + i * root.barPitch;
                _bar(ctx, x, cy, amp);
            }
            ctx.globalAlpha = 1.0;
        }

        function _paintBars(ctx, left, alpha) {
            ctx.globalAlpha = alpha;
            const x0 = left + root.padLeft + root.dotDiameter + root.gapAfterDot;
            const cy = root.pillHeight / 2;
            const n  = root.barCount;
            const lv = root.levels;

            _setGradient(ctx, x0, x0 + n * root.barPitch);

            for (let i = 0; i < n; i++) {
                const level = lv.length === n ? lv[i] : 0.0;
                const amp = root.barMinHeight / 2 + level * root.barMaxAmp;
                const x = x0 + i * root.barPitch;
                _bar(ctx, x, cy, amp);
            }
            ctx.globalAlpha = 1.0;
        }
    }
}

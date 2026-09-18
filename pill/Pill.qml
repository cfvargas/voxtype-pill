// Rediseño del OSD de voxtype: píldora con punto de grabación y traza de
// barras finas con degradado horizontal. Reproduce docs/actual.png.
//
// Contrato con OsdSurface.qml: el Loader llena toda la pantalla y nos
// inyecta estas propiedades, así que el posicionamiento es cosa nuestra.
// Los tipos de capa integrados no sirven aquí: `bars` topa en 28 barras
// con degradado vertical, y el diseño pide ~72 finas de azul a magenta.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // --- inyectadas por OsdSurface._syncCustomItem() ---
    property string daemonState: "idle"
    property var audio: null
    property var theme: null      // VT.StyleLoader
    property var recipe: null
    property string assetRoot: ""

    // ---------------------------------------------------------------
    // Diseño. Medidas tomadas del mockup (píldora de 447x60 sobre 1280).
    // ---------------------------------------------------------------
    readonly property int  pillWidth:      253         // ancho grabando (dos tercios de 380)
    readonly property int  pillWidthMin:   110         // ancho transcribiendo, ajustado a la onda mini
    readonly property int  pillHeight:      50
    readonly property real pillRadius:      pillHeight / 2

    // Ancho actual: se interpola con el cruce grabación<->transcripción, así
    // que la píldora se encoge alrededor de los tres puntos de forma animada.
    // _transProgress ya viene suavizado, el encogimiento hereda esa curva.
    readonly property real curPillWidth:
        pillWidth + (pillWidthMin - pillWidth) * _transProgress

    // ---------------------------------------------------------------
    // Colores: siguen al tema activo de Omarchy.
    //
    // Los roles que expone el launcher (`theme.color`) son pocos y algunos
    // van fijos — `recording` es siempre #F2594D, no el rojo del tema — así
    // que se lee colors.toml del tema directamente (ver FileView abajo).
    // Todos los temas de Omarchy traen los ocho colores base, así que el
    // mapeo vale para cualquiera. Cada valor cae al mockup si falta.
    // ---------------------------------------------------------------
    property var themeColors: ({})

    function _tc(key, fallback) {
        const v = themeColors[key];
        return (typeof v === "string" && v.length === 7) ? v : fallback;
    }

    // Cuatro claves del tema y nada más: el fondo, el rojo y dos para las
    // barras. El borde no gasta clave: se deriva aclarando el fondo.
    readonly property string bgHex:     _tc("dark_background", _tc("background", "#0B121A"))
    readonly property color  pillColor:  _withAlpha(bgHex, 0.99)
    readonly property color  pillBorder: _mix(bgHex, "#FFFFFF", 0.14)
    readonly property color  dotColor:   _tc("red", "#E73B36")

    // Barras: del color de identidad del tema (accent, que en casi todos es
    // el azul) al magenta. Conserva el gesto del mockup — el primer color
    // aguanta un tercio y solo entonces vira — con dos colores en vez de cinco.
    readonly property string gradA: _tc("accent", _tc("blue", "#6683D4"))
    readonly property string gradB: _tc("magenta", "#9A5CD5")
    readonly property var gradientStops: [
        { at: 0.00, color: gradA },
        { at: 0.35, color: gradA },
        { at: 1.00, color: gradB }
    ]

    // "#RRGGBB" + alpha 0..1 -> "#AARRGGBB", la forma que entienden QML y Canvas.
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

    // Estado "transcribing": la misma onda, condensada. Mientras el modelo
    // procesa no hay audio, así que las barras las mueve un pulso sintético
    // que recorre la burbuja de izquierda a derecha sin parar: el audio que
    // grabaste "sigue pasando por dentro" mientras se convierte en texto.
    // Comparte barras y degradado con la grabación, así el fundido entre
    // los dos estados no cambia de idioma visual.
    readonly property int  pulsePad:      23            // borde -> primera barra
    readonly property real pulseMaxAmp:   12            // algo más calmo que grabando
    readonly property real pulseSpeed:     1.15         // recorridos por segundo (~1.5 s)
    readonly property real pulseFront:     0.08         // sigma del frente (nítido)
    readonly property real pulseTail:      0.20         // sigma de la cola (larga)
    readonly property real pulseBreath:    0.06         // latido de fondo, nunca plana

    readonly property int  dotDiameter:  16
    readonly property int  padLeft:      20             // borde -> punto
    readonly property int  gapAfterDot:  18             // punto -> barras
    readonly property int  padRight:     16

    readonly property real barWidth:      3
    readonly property real barPitch:      5             // centro a centro
    readonly property real barMinHeight:  2.5           // silencio = puntitos
    readonly property real barMaxAmp:     14            // pico, desde el centro

    // Suavizado de la señal antes de dibujarla. El peak crudo del daemon
    // salta muy rápido (100 Hz) y la traza se ve nerviosa; con ataque rápido
    // y caída lenta las barras suben con energía al hablar y se relajan con
    // gracia al callar, en vez de cortar en seco.
    readonly property real attackPerFrame:  0.55        // subida (0..1 por frame)
    readonly property real releasePerFrame: 0.07        // bajada, más lenta

    // Ganancia visual: los picos de voz en mic rondan 0.1-0.3 de escala
    // completa, así que sin ganancia la traza sería una línea plana.
    readonly property real gain: _cfgNum("waveform_gain", 10.0)

    // ---------------------------------------------------------------
    // Posición: la manda la config, igual que en el surface integrado.
    // Ojo: en los anclajes centrados la vertical la fija `top_margin`
    // (fracción de la altura del monitor), NO la palabra top/bottom.
    // ---------------------------------------------------------------
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

    // ---------------------------------------------------------------
    // Señal de audio: historial de picos, el más reciente a la derecha.
    // ---------------------------------------------------------------
    readonly property int barCount:
        Math.max(1, Math.floor((pillWidth - padLeft - dotDiameter - gapAfterDot - padRight) / barPitch))

    property var levels: []          // nivel suavizado por barra, 0..1
    property real _lastTick: Date.now()
    property real _level: 0.0         // nivel con ataque/caída, lo que se empuja

    // Progreso del cruce barras<->puntos (0 = grabando, 1 = transcribiendo).
    // Se anima para que soltar la tecla no corte en seco entre una vista y
    // la otra, sino que una se funda en la otra.
    property real _transProgress: 0.0

    // Modo demo (VOXTYPE_PILL_DEMO=1): sintetiza una envolvente tipo voz
    // para poder revisar el diseño con amplitud real sin usar el micrófono.
    // Solo afecta al dibujo; no toca la captura de audio.
    readonly property bool demo: Quickshell.env("VOXTYPE_PILL_DEMO") === "1"
    property real _demoPhase: 0

    // Fase de animación, avanza siempre que el widget está visible.
    property real _phase: 0

    // Forzador de estado para capturas (VOXTYPE_PILL_STATE=transcribing).
    // Solo afecta al dibujo: el estado real del daemon no se toca.
    readonly property string stateOverride: Quickshell.env("VOXTYPE_PILL_STATE") || ""
    readonly property string drawState: stateOverride.length > 0 ? stateOverride : daemonState

    readonly property bool transcribing: drawState === "transcribing"

    // Barras que caben en la burbuja encogida, centradas.
    readonly property int pulseBarCount:
        Math.max(3, Math.floor((pillWidthMin - 2 * pulsePad) / barPitch))

    // Fase propia del pulso: arranca en cero al entrar en transcripción para
    // que el primer recorrido ENTRE por la izquierda justo cuando la píldora
    // colapsa — la energía de la grabación parece meterse en la burbuja.
    property real _pulsePhase: 0.0
    onTranscribingChanged: if (transcribing) _pulsePhase = 0.0

    // Nivel 0..1 de la barra en posición t (0 = izq, 1 = der) para el pulso
    // viajero. Frente nítido y cola larga: se lee como energía que fluye, no
    // como una bola que rebota. Un latido leve de fondo evita que la burbuja
    // quede plana entre un recorrido y el siguiente.
    // Un solo pulso dejaba la burbuja plana entre recorrido y recorrido, y
    // al dar la vuelta cortaba la cola en seco (todavía medía ~22 % en el
    // borde derecho cuando reaparecía por la izquierda). El recorrido va de
    // -0.25 a 1.65 para que frente y cola salgan del todo (3 sigmas), y un
    // segundo pulso a media distancia y menor altura mantiene el flujo.
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

    // Suavizado temporal asimétrico: sube rápido, baja lento. Da inercia
    // de vúmetro en vez de parpadeo muestra a muestra.
    function _approach(current, target, stiffness, dt) {
        return current + (target - current) * (1 - Math.exp(-Math.max(0.01, stiffness) * dt));
    }

    Component.onCompleted: { _resetLevels(); _reloadTheme(); }

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
            // El widget solo se ve al grabar: releer el tema en cada aparición
            // garantiza colores frescos sin polling. Hace falta porque
            // watchChanges no ve el cambio de tema (ver FileView), y un
            // reload() a secas tampoco basta: omarchy-theme-set hace rm+mv
            // sobre current/theme, así que el FileView sigue apuntando al
            // inode viejo borrado. El path-flip lo obliga a reabrir la ruta.
            _reloadTheme();
        }
    }

    // Cada frame del daemon desplaza el historial una barra a la izquierda.
    // El valor que entra no es el peak crudo sino uno con ataque/caída, así
    // que el borde derecho de la traza sube y baja con suavidad.
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

    // Envolvente sintética: sílabas sobre una portadora lenta, más fuerte
    // hacia la derecha, como la traza del mockup.
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

    // ---------------------------------------------------------------
    // Tema de Omarchy: colors.toml del tema activo. El estado moderno vive
    // en ~/.local/state; el legado en ~/.config.
    //
    // OJO: `watchChanges` NO detecta el cambio de tema. omarchy-theme-set
    // monta el tema nuevo en una carpeta aparte y la renombra encima de
    // current/theme, así que el inode vigilado queda huérfano y nunca llega
    // aviso. Por eso el tema se recarga cada vez que el widget aparece
    // (onDaemonStateChanged) y, de refuerzo, al cambiar theme.name.
    // ---------------------------------------------------------------
    readonly property string _home: Quickshell.env("HOME") || ""
    // VOXTYPE_PILL_THEME_FILE fuerza la ruta del colors.toml (para pruebas
    // aisladas); si está vacía, se usan las rutas reales de Omarchy.
    readonly property string _themeOverride: Quickshell.env("VOXTYPE_PILL_THEME_FILE") || ""

    // Parser mínimo: solo líneas `clave = "#rrggbb"`, que es todo lo que
    // trae el archivo. No hace falta un parser TOML para esto.
    function _parseTheme(text) {
        const out = {};
        const re = /^\s*([A-Za-z_]+)\s*=\s*"(#[0-9A-Fa-f]{6})"/;
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const m = re.exec(lines[i]);
            if (m) out[m[1]] = m[2].toUpperCase();
        }
        if (Object.keys(out).length > 0) {   // no pisar con vacío si cat falla
            themeColors = out;
            canvas.requestPaint();
        }
    }

    // Relee el tema con `cat`. FileView no vale aquí: omarchy-theme-set hace
    // rm+mv sobre current/theme, así que queda colgado del inode viejo y ni
    // watchChanges ni reload()/path-flip releen fiable. Un `cat` nuevo lee
    // siempre el contenido actual de la ruta, sin importar el inode. Prueba
    // .local/state y cae a .config (o a la ruta forzada en pruebas).
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

    // Refuerzo: theme.name es pequeño y theme-set lo reescribe en cada cambio.
    // Si el compositor propaga el evento, el widget se recolorea sin esperar a
    // la siguiente grabación. El watcher puede no dispararse tras el rm+mv,
    // por eso el disparo fiable es onDaemonStateChanged (cada aparición).
    FileView {
        id: themeNameFile
        path: root._home + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onFileChanged: root._reloadTheme()
    }

    // ---------------------------------------------------------------
    // Dibujo
    // ---------------------------------------------------------------
    Canvas {
        id: canvas
        x: root._pillX() - 24          // margen para el glow del borde
        y: root._pillY() - 24
        width:  root.pillWidth  + 48
        height: root.pillHeight + 48
        antialiasing: true

        readonly property real ox: 24   // origen de la píldora dentro del canvas
        readonly property real oy: 24

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.translate(ox, oy);

            // La píldora encoge hacia el centro del canvas; su contenido se
            // recorta al borde, así las barras "entran" tras el borde a
            // medida que se estrecha, en vez de quedar flotando fuera.
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

        // Onda mini de la transcripción: las mismas barras y el mismo
        // degradado que grabando, centradas en la burbuja, movidas por el
        // pulso viajero. `alpha` la funde con la vista de grabación.
        function _paintPulse(ctx, left, w, alpha) {
            const n    = root.pulseBarCount;
            const span = (n - 1) * root.barPitch + root.barWidth;
            const x0   = left + (w - span) / 2;
            const cy   = root.pillHeight / 2;

            const grad = ctx.createLinearGradient(x0, 0, x0 + span, 0);
            for (let s = 0; s < root.gradientStops.length; s++) {
                grad.addColorStop(root.gradientStops[s].at, root.gradientStops[s].color);
            }
            ctx.fillStyle = grad;
            ctx.globalAlpha = alpha;

            for (let i = 0; i < n; i++) {
                const t     = n <= 1 ? 0.5 : i / (n - 1);
                const level = root._pulseLevel(t);
                const amp   = root.barMinHeight / 2 + level * root.pulseMaxAmp;
                const x     = x0 + i * root.barPitch;
                _roundedRect(ctx, x, cy - amp, root.barWidth, amp * 2, root.barWidth / 2);
                ctx.fill();
            }
            ctx.globalAlpha = 1.0;
        }

        function _paintBars(ctx, left, alpha) {
            ctx.globalAlpha = alpha;
            const x0 = left + root.padLeft + root.dotDiameter + root.gapAfterDot;
            const cy = root.pillHeight / 2;
            const n  = root.barCount;
            const lv = root.levels;

            // Degradado horizontal a lo largo de la traza: el built-in
            // `bars` solo sabe hacerlo vertical, de ahí este QML.
            const grad = ctx.createLinearGradient(x0, 0, x0 + n * root.barPitch, 0);
            for (let s = 0; s < root.gradientStops.length; s++) {
                grad.addColorStop(root.gradientStops[s].at, root.gradientStops[s].color);
            }
            ctx.fillStyle = grad;

            for (let i = 0; i < n; i++) {
                const level = lv.length === n ? lv[i] : 0.0;
                const amp = root.barMinHeight / 2 + level * root.barMaxAmp;
                const x = x0 + i * root.barPitch;
                const h = amp * 2;
                _roundedRect(ctx, x, cy - amp, root.barWidth, h, root.barWidth / 2);
                ctx.fill();
            }
            ctx.globalAlpha = 1.0;
        }
    }
}

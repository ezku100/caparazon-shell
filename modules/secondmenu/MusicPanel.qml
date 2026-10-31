import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"
import "../music"
import "../music/ArtUrls.js" as ArtUrls

/*
  Categoría Música del menú secundario.
  Mismo lenguaje visual que CalendarPanel: tarjetas Theme.chip, radio 16,
  Theme.fontUI.

  Layout:
  - Izquierda: álbum con el vinilo asomando por detrás (la mitad se ve).
  - Derecha: letra. Si no hay letra, la tarjeta se oculta y el álbum se centra.
  - Abajo: tarjeta con barra de progreso (con seek) y controles
    aleatorio · anterior · play/pausa · siguiente · repetir.
*/
Item {
    id: root

    // ── Reproductor MPRIS ─────────────────────────────────────────────
    readonly property var players: Mpris.players && Mpris.players.values ? Mpris.players.values : []
    readonly property var candidates: {
        const list = [];
        for (let i = 0; i < players.length; ++i) {
            const p = players[i];
            if (p && (p.isPlaying || p.trackTitle !== "")) list.push(p);
        }
        return list;
    }

    // Reproductor elegido manualmente (rueda o botones); null = automático.
    property var pinnedPlayer: null

    readonly property var player: {
        if (pinnedPlayer && candidates.indexOf(pinnedPlayer) !== -1)
            return pinnedPlayer;
        // Automático: el último que está sonando de verdad...
        for (let i = candidates.length - 1; i >= 0; --i) {
            if (candidates[i].isPlaying)
                return candidates[i];
        }
        // ...y si no hay reproducción, el último con una pista pausada.
        return candidates.length > 0 ? candidates[candidates.length - 1] : null;
    }

    // Cambia de reproductor: delta=-1 anterior, +1 siguiente.
    function cyclePlayer(delta) {
        const count = candidates.length;
        if (count < 2)
            return;
        let index = candidates.indexOf(player);
        if (index < 0)
            index = count - 1;
        pinnedPlayer = candidates[(index + delta + count) % count];
    }

    // Si el elegido está en pausa y empieza a sonar otro, vuelve al automático.
    readonly property string playingSignature: {
        let key = "";
        for (let i = 0; i < candidates.length; ++i) {
            if (candidates[i].isPlaying)
                key += i + ",";
        }
        return key;
    }

    onPlayingSignatureChanged: {
        if (!pinnedPlayer || pinnedPlayer.isPlaying)
            return;
        for (let i = 0; i < candidates.length; ++i) {
            if (candidates[i] !== pinnedPlayer && candidates[i].isPlaying) {
                pinnedPlayer = null;
                return;
            }
        }
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool playing: hasPlayer && player.isPlaying

    // Carátulas a probar, en orden: la que manda el reproductor y, si no la
    // hay, la miniatura del vídeo. Los navegadores no mandan mpris:artUrl
    // cuando suena YouTube: sólo dan la URL del vídeo.
    readonly property var artCandidates: ArtUrls.artCandidates(player)
    property int artIndex: 0
    // Acumulador para el cambio de reproductor con rueda del ratón sobre el cover
    property real wheelAccum: 0

    readonly property string artKey: artCandidates.join("|")
    onArtKeyChanged: artIndex = 0

    readonly property string artUrl: artIndex < artCandidates.length
        ? artCandidates[artIndex]
        : ""

    // Si una carátula no carga, se pasa a la siguiente.
    function artFailed(url) {
        if (String(url || "") !== root.artUrl)
            return;
        if (root.artIndex < root.artCandidates.length - 1)
            root.artIndex += 1;
    }

    readonly property string rawTitle: player ? (player.trackTitle || "") : ""
    readonly property string rawArtist: player ? (player.trackArtist || "") : ""
    readonly property string rawAlbum: player ? (player.trackAlbum || "") : ""

    readonly property string trackTitle: hasPlayer ? (rawTitle || "Sin título") : "Sin reproducción"
    readonly property string trackArtist: hasPlayer ? (rawArtist || player.identity || "") : "Abre un reproductor"

    // ── Progreso (Quickshell expone position y length en SEGUNDOS) ────
    readonly property bool hasLength: hasPlayer && player.lengthSupported && player.length > 0
    readonly property bool canSeek: hasLength && player.canSeek && player.positionSupported
    property real displayPosition: 0
    readonly property real progress: hasLength
        ? Math.max(0, Math.min(1, displayPosition / player.length)) : 0

    // Interpolación entre lecturas de MPRIS (para el relleno por palabras)
    property real posBase: 0
    property double posStamp: 0
    property real smoothPos: 0

    function syncPosition() {
        displayPosition = player ? Math.max(0, Number(player.position) || 0) : 0;
        const est = posBase + (Date.now() - posStamp) / 1000;
        // Si la estimación va cerca de la lectura real no la tocamos: evita tirones.
        if (!(playing && Math.abs(displayPosition - est) < 0.3)) {
            posBase = displayPosition;
            posStamp = Date.now();
            smoothPos = displayPosition;
        }
    }

    FrameAnimation {
        running: root.playing && root.hasWords && root.visible
        onTriggered: root.smoothPos = root.posBase + (Date.now() - root.posStamp) / 1000
    }

    function seekTo(ratio) {
        if (!canSeek) return;
        const target = Math.max(0, Math.min(1, ratio)) * player.length;
        player.position = target;
        displayPosition = target;
        posBase = target;
        posStamp = Date.now();
        smoothPos = target;
    }

    function formatTime(secs) {
        if (secs === undefined || secs === null || isNaN(secs)) return "--:--";
        const s = Math.max(0, Math.floor(secs));
        const m = Math.floor(s / 60);
        const sec = s % 60;
        return m + ":" + (sec < 10 ? "0" + sec : sec);
    }

    onPlayerChanged: {
        syncPosition();
        lyricsDebounce.restart();
    }
    onRawTitleChanged: lyricsDebounce.restart()
    onRawArtistChanged: lyricsDebounce.restart()

    Timer {
        interval: root.hasSynced ? 150 : 500
        repeat: true
        running: root.playing
        // MPRIS no emite la posición sola: hay que pedirla.
        onTriggered: if (root.player) root.player.positionChanged()
    }

    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged() { if (!seek.dragging) root.syncPosition(); }
        function onLengthChanged() { root.syncPosition(); }
        function onTrackTitleChanged() { root.syncPosition(); }
        function onIsPlayingChanged() { root.syncPosition(); }
    }

    // ── Aleatorio / repetir ───────────────────────────────────────────
    readonly property bool shuffleOn: hasPlayer && player.shuffleSupported && player.shuffle
    readonly property bool loopSupported: hasPlayer && player.loopSupported
    readonly property bool loopOn: loopSupported && player.loopState !== MprisLoopState.None
    readonly property bool loopTrack: loopSupported && player.loopState === MprisLoopState.Track

    function toggleShuffle() {
        if (hasPlayer && player.shuffleSupported)
            player.shuffle = !player.shuffle;
    }

    // Ciclo: sin repetir → lista → pista → sin repetir
    function cycleLoop() {
        if (!loopSupported) return;
        const s = player.loopState;
        if (s === MprisLoopState.None) player.loopState = MprisLoopState.Playlist;
        else if (s === MprisLoopState.Playlist) player.loopState = MprisLoopState.Track;
        else player.loopState = MprisLoopState.None;
    }

    // ── Letras ────────────────────────────────────────────────────────
    LyricsService {
        id: lyricsService
    }

    // Espera a que artista y título se asienten antes de consultar.
    Timer {
        id: lyricsDebounce
        interval: 400
        onTriggered: lyricsService.fetchFor(root.rawArtist, root.rawTitle, root.rawAlbum,
                                            root.hasLength ? root.player.length : 0)
    }

    // Quita marcas de tiempo [00:12.34] y etiquetas [ar:...] si vinieran en LRC.
    function cleanLyrics(text) {
        return String(text || "")
            .replace(/^\s*\[[a-zA-Z]+:[^\]]*\]\s*$/gm, "")
            .replace(/\[\d+:\d+(?:[.:]\d+)?\]/g, "")
            .replace(/\n{3,}/g, "\n\n")
            .trim();
    }

    readonly property string lyricsText: cleanLyrics(lyricsService.plainLyrics || lyricsService.lyrics)

    // LRC (normal o "mejorado" con <mm:ss.xx> por palabra) →
    // [{ t, text, words: [{ t, e, text, space }] }] ordenado por tiempo.
    function parseLrc(text) {
        const out = [];
        const rows = String(text || "").split(/\r?\n/);
        const stamp = (m, s2, f) => Number(m) * 60 + Number(s2) + (f ? Number("0." + f) : 0);

        for (let i = 0; i < rows.length; ++i) {
            const m = /^\s*((?:\[\d+:\d+(?:[.:]\d+)?\])+)(.*)$/.exec(rows[i]);
            if (!m) continue;

            const body = m[2];
            const words = [];
            const wre = /<(\d+):(\d+)(?:[.:](\d+))?>([^<]*)/g;
            let wm;
            while ((wm = wre.exec(body)) !== null) {
                const t = stamp(wm[1], wm[2], wm[3]);
                const raw = wm[4];
                const txt = raw.trim();
                if (txt === "") {
                    // marca de fin de la última palabra
                    if (words.length) {
                        words[words.length - 1].end = t;
                        words[words.length - 1].space = true;
                    }
                    continue;
                }
                if (/^\s/.test(raw) && words.length) words[words.length - 1].space = true;
                words.push({ t: t, e: t, end: -1, text: txt, space: /\s$/.test(raw) });
            }

            const plain = body.replace(/<\d+:\d+(?:[.:]\d+)?>/g, "").replace(/\s+/g, " ").trim();
            const re = /\[(\d+):(\d+)(?:[.:](\d+))?\]/g;
            let tm, count = 0;
            while ((tm = re.exec(m[1])) !== null) {
                out.push({
                    t: stamp(tm[1], tm[2], tm[3]),
                    text: plain,
                    words: count === 0 ? words : []   // con varias marcas, solo la primera lleva palabras
                });
                count += 1;
            }
        }

        out.sort((a, b) => a.t - b.t);

        // Fin de cada palabra: inicio de la siguiente, o el fin de la línea.
        for (let i = 0; i < out.length; ++i) {
            const ws = out[i].words;
            if (!ws.length) continue;
            const lineEnd = i + 1 < out.length ? out[i + 1].t : out[i].t + 4;
            for (let j = 0; j < ws.length; ++j) {
                let e = j + 1 < ws.length ? ws[j + 1].t
                    : (ws[j].end > ws[j].t ? ws[j].end : Math.min(lineEnd, ws[j].t + 2.5));
                ws[j].e = Math.max(e, ws[j].t + 0.05);
            }
        }
        return out;
    }

    readonly property var syncedLines: parseLrc(lyricsService.lyrics)
    readonly property bool hasSynced: syncedLines.length > 0
    readonly property bool hasWords: {
        for (let i = 0; i < syncedLines.length; ++i)
            if (syncedLines[i].words.length > 0) return true;
        return false;
    }
    readonly property bool hasLyrics: hasSynced || lyricsText.length > 0

    // Posición para la letra: con palabras se interpola a cada fotograma
    // para que el relleno avance suave y no a saltos de 150 ms.
    readonly property real lyricsPos: hasWords ? smoothPos : displayPosition
    // Como en el plugin de Noctalia: la línea avanza con 0.4 s de adelanto y
    // solo retrocede ante un salto real (>1 s), así el jitter de MPRIS no la
    // hace parpadear. Con palabras el adelanto es menor para que el relleno
    // coincida con la voz.
    readonly property real lyricsLead: hasWords ? 0.15 : 0.4
    property int currentLine: -1

    function updateCurrentLine() {
        const lines = syncedLines;
        if (!lines.length) {
            currentLine = -1;
            return;
        }
        let i = Math.min(currentLine, lines.length - 1);
        while (i + 1 < lines.length && lines[i + 1].t <= lyricsPos + lyricsLead)
            i += 1;
        while (i >= 0 && lines[i].t > lyricsPos + 1.0)
            i -= 1;
        if (i !== currentLine) currentLine = i;
    }

    onLyricsPosChanged: updateCurrentLine()
    onSyncedLinesChanged: {
        currentLine = -1;
        updateCurrentLine();
    }

    Component.onCompleted: {
        syncPosition();
        lyricsDebounce.restart();
    }

    // ── Botón multimedia dibujado (no depende de fuentes ni de iconos) ─
    component MediaButton: Item {
        id: btn

        property string glyph: "play"      // play pause prev next shuffle repeat
        property string badge: ""          // texto pequeño encima del icono (p. ej. "1")
        property bool available: true
        property bool active: false        // aleatorio / repetir encendidos
        property bool filled: false        // botón principal (play)
        property int diameter: 40
        property int iconSize: 20

        signal clicked()

        width: diameter
        height: diameter

        readonly property color fg: !available ? Theme.textDim
            : filled ? Theme.m3OnPrimary
            : active ? Theme.m3Primary
            : Theme.text

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: btn.filled ? Theme.m3Primary
                : (hover.hovered && btn.available ? Theme.chipHover : "transparent")
            opacity: btn.filled && !btn.available ? 0.4 : 1
        }

        Canvas {
            id: cv
            anchors.centerIn: parent
            width: btn.iconSize
            height: btn.iconSize
            opacity: btn.available ? 1 : 0.45

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.scale(width / 24, height / 24);
                ctx.fillStyle = btn.fg;
                ctx.strokeStyle = btn.fg;
                ctx.lineWidth = 2;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";

                function tri(x1, y1, x2, y2, x3, y3) {
                    ctx.beginPath();
                    ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.lineTo(x3, y3);
                    ctx.closePath();
                    ctx.fill();
                }

                switch (btn.glyph) {
                case "play":
                    tri(7, 4, 7, 20, 20, 12);
                    break;
                case "pause":
                    ctx.fillRect(6, 4, 4, 16);
                    ctx.fillRect(14, 4, 4, 16);
                    break;
                case "prev":
                    ctx.fillRect(4.5, 5, 2.5, 14);
                    tri(20, 5, 20, 19, 8, 12);
                    break;
                case "next":
                    ctx.fillRect(17, 5, 2.5, 14);
                    tri(4, 5, 4, 19, 16, 12);
                    break;
                case "shuffle":
                    ctx.beginPath();
                    ctx.moveTo(2.5, 7); ctx.lineTo(7, 7);
                    ctx.bezierCurveTo(12, 7, 12, 17, 17, 17);
                    ctx.lineTo(18.5, 17);
                    ctx.moveTo(2.5, 17); ctx.lineTo(7, 17);
                    ctx.bezierCurveTo(12, 17, 12, 7, 17, 7);
                    ctx.lineTo(18.5, 7);
                    ctx.stroke();
                    tri(18, 3.5, 23, 7, 18, 10.5);
                    tri(18, 13.5, 23, 17, 18, 20.5);
                    break;
                case "repeat":
                    ctx.beginPath();
                    ctx.moveTo(3.5, 12); ctx.lineTo(3.5, 10);
                    ctx.quadraticCurveTo(3.5, 6.5, 7, 6.5);
                    ctx.lineTo(16.5, 6.5);
                    ctx.moveTo(20.5, 12); ctx.lineTo(20.5, 14);
                    ctx.quadraticCurveTo(20.5, 17.5, 17, 17.5);
                    ctx.lineTo(7.5, 17.5);
                    ctx.stroke();
                    tri(16, 3, 21, 6.5, 16, 10);
                    tri(8, 14, 3, 17.5, 8, 21);
                    break;
                }
            }

            Connections {
                target: btn
                function onFgChanged() { cv.requestPaint(); }
                function onGlyphChanged() { cv.requestPaint(); }
            }
            Component.onCompleted: requestPaint()
        }

        Text {
            visible: btn.badge.length > 0
            anchors.centerIn: parent
            text: btn.badge
            color: btn.fg
            font.family: Theme.fontUI
            font.pixelSize: 8
            font.weight: Font.Bold
        }

        // Puntito de "encendido" bajo aleatorio / repetir
        Rectangle {
            visible: btn.active && !btn.filled
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            width: 4
            height: 4
            radius: 2
            color: Theme.m3Primary
        }

        HoverHandler {
            id: hover
            enabled: btn.available
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            enabled: btn.available
            acceptedButtons: Qt.LeftButton
            onClicked: btn.clicked()
        }
    }

    // ── Modo compacto ────────────────────────────────────────────────
    // Recordado entre aperturas: el servicio guarda la elección.
    MusicSettings {
        id: compactSettings
    }

    readonly property bool compact: compactSettings.compact

    function toggleCompact() {
        compactSettings.compact = !compactSettings.compact;
    }

    // ── Layout ────────────────────────────────────────────────────────
    Column {
        id: layout
        anchors.fill: parent
        spacing: 12

        // ── Cuerpo: álbum + vinilo | letra ────────────────────────────
        Item {
            id: body
            width: layout.width
            height: layout.height
                - (root.compact ? spectrum.height : controlsCard.height)
                - layout.spacing

            // Escenario del álbum: ocupa todo el ancho si no hay letra.
            Item {
                id: stage
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.hasLyrics && !root.compact
                    ? Math.round(body.width * 0.5)
                    : body.width

                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // Lado del álbum cuadrado. El conjunto álbum+vinilo mide ~1.44 × lado.
                readonly property real coverSize: Math.max(90,
                    Math.min(stage.height - 62, (stage.width - 8) / 1.44))
                readonly property real vinylSize: coverSize * 0.92

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Item {
                        id: discs
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: stage.coverSize * 1.44
                        height: stage.coverSize

                        // Pausado: el vinilo se esconde tras el álbum y el álbum se
                        // centra; al reproducir, el vinilo sale y el álbum se mueve.
                        readonly property real shift: root.playing ? 0 : stage.coverSize * 0.22

                        // Rueda sobre el álbum: cambia entre reproductores. Va en
                        // este bloque y no en la imagen para que también funcione
                        // cuando no hay carátula (la imagen oculta no recibe
                        // eventos de rueda).
                        HoverHandler {
                            id: discsHover
                        }

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: function(event) {
                                if (root.candidates.length < 2) return;
                                if (root.wheelAccum * event.angleDelta.y < 0)
                                    root.wheelAccum = 0;
                                root.wheelAccum += event.angleDelta.y;
                                if (Math.abs(root.wheelAccum) >= 120) {
                                    root.cyclePlayer(root.wheelAccum > 0 ? -1 : 1);
                                    root.wheelAccum = 0;
                                }
                            }
                        }

                        // Vinilo: detrás del álbum, sobresale por la derecha
                        Item {
                            id: vinyl
                            width: stage.vinylSize
                            height: stage.vinylSize
                            x: discs.shift + (root.playing
                                ? stage.coverSize * 0.98 - width / 2
                                : (stage.coverSize - width) / 2)
                            y: (stage.coverSize - height) / 2

                            Behavior on x {
                                NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
                            }

                            // Cuerpo del disco: se pinta una sola vez y gira como textura.
                            // El brillo cónico (dos destellos) es asimétrico a propósito:
                            // así el giro se nota aunque el centro quede tapado por el álbum.
                            Canvas {
                                id: vinylBody
                                anchors.fill: parent
                                onWidthChanged: requestPaint()

                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();
                                    const w = width, c = w / 2, r = c - 1;
                                    const full = 2 * Math.PI;

                                    ctx.fillStyle = "#141414";
                                    ctx.beginPath();
                                    ctx.arc(c, c, r, 0, full);
                                    ctx.fill();

                                    const g = ctx.createConicalGradient(c, c, 0);
                                    g.addColorStop(0.00, "rgba(255,255,255,0)");
                                    g.addColorStop(0.05, "rgba(255,255,255,0.22)");
                                    g.addColorStop(0.13, "rgba(255,255,255,0)");
                                    g.addColorStop(0.50, "rgba(255,255,255,0)");
                                    g.addColorStop(0.55, "rgba(255,255,255,0.15)");
                                    g.addColorStop(0.63, "rgba(255,255,255,0)");
                                    g.addColorStop(1.00, "rgba(255,255,255,0)");
                                    ctx.fillStyle = g;
                                    ctx.beginPath();
                                    ctx.arc(c, c, r, 0, full);
                                    ctx.fill();

                                    // Surcos
                                    ctx.lineWidth = 1;
                                    ctx.strokeStyle = "rgba(255,255,255,0.08)";
                                    for (let k = 0; k < 6; ++k) {
                                        ctx.beginPath();
                                        ctx.arc(c, c, r * (0.94 - k * 0.075), 0, full);
                                        ctx.stroke();
                                    }

                                    ctx.strokeStyle = "#2e2e2e";
                                    ctx.beginPath();
                                    ctx.arc(c, c, r, 0, full);
                                    ctx.stroke();
                                }
                            }

                            // Etiqueta: la carátula recortada en círculo (gira con el disco)
                            ClippingRectangle {
                                id: vinylLabel
                                anchors.centerIn: parent
                                width: vinyl.width * 0.46
                                height: width
                                radius: width / 2
                                color: Theme.m3Primary

                                Image {
                                    anchors.fill: parent
                                    source: root.artUrl
                                    sourceSize.width: 128
                                    sourceSize.height: 128
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                    visible: status === Image.Ready && root.artUrl !== ""

                                    onStatusChanged: {
                                        if (status === Image.Error)
                                            root.artFailed(source);
                                    }
                                }
                            }

                            // Anillo oscuro alrededor de la etiqueta y agujero central
                            Rectangle {
                                anchors.centerIn: parent
                                width: vinylLabel.width + 4
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: 2
                                border.color: "#141414"
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: Theme.surface
                                border.width: 1
                                border.color: "#141414"
                            }

                            // Giro continuo; se detiene sin saltos al pausar
                            FrameAnimation {
                                running: root.playing
                                onTriggered: vinyl.rotation = (vinyl.rotation + frameTime * 36) % 360
                            }
                        }

                        // Álbum, encima del vinilo
                        ClippingRectangle {
                            id: coverBox
                            x: discs.shift

                            Behavior on x {
                                NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
                            }

                            width: stage.coverSize
                            height: stage.coverSize
                            radius: 14
                            color: Theme.m3SurfaceContainerLow
                            border.width: 1
                            border.color: Theme.m3OutlineVariant

                            Image {
                                id: coverImage
                                anchors.fill: parent
                                source: root.artUrl
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true
                                cache: false
                                visible: status === Image.Ready && root.artUrl !== ""

                                onStatusChanged: {
                                    if (status === Image.Error)
                                        root.artFailed(source);
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !coverImage.visible
                                text: "♪"
                                color: Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 40
                            }
                        }

                        // Clic en el álbum: pausa o reanuda. En modo compacto
                        // es la única forma de parar la música, porque los
                        // botones de transporte están ocultos. Convive con la
                        // rueda, que cambia de reproductor.
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.hasPlayer && root.player.canTogglePlaying
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.player.togglePlaying()
                        }
                    }

                    // Título y artista (cambio de reproductor en la esquina inferior)
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(stage.width - 16, 360)
                        spacing: 4

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: root.trackTitle
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    // Artista
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.trackArtist
                            + (root.rawAlbum ? "  ·  " + root.rawAlbum : "")
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.hasPlayer && !root.hasLyrics
                        text: lyricsService.status === "loading" ? "Buscando letra…"
                            : lyricsService.status === "error" ? "No se pudo consultar la letra"
                            : lyricsService.status === "empty" ? "Sin letra en LRCLIB"
                            : ""
                        color: Theme.textDim
                        opacity: 0.7
                        font.family: Theme.fontUI
                        font.pixelSize: 10
                    }
                }
            }

            // Letra (oculta si no existe)
            Rectangle {
                id: lyricsCard
                anchors.left: stage.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: 16
                color: Theme.chip
                clip: true
                opacity: root.hasLyrics ? 1 : 0
                visible: opacity > 0 && !root.compact

                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }

                // Letra sincronizada: la línea actual se centra y se resalta.
                // Clic en una línea = saltar a ese momento.
                ListView {
                    id: lyricsList
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: root.hasSynced
                    clip: true
                    interactive: false
                    model: root.syncedLines
                    currentIndex: Math.max(0, root.currentLine)
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: height / 2 - 24
                    preferredHighlightEnd: height / 2 + 24
                    highlightMoveDuration: 380
                    highlightMoveVelocity: -1
                    highlight: Item {}

                    header: Item { width: 1; height: lyricsList.height / 2 - 24 }
                    footer: Item { width: 1; height: lyricsList.height / 2 - 24 }

                    delegate: Item {
                        id: lineItem
                        required property int index
                        required property var modelData

                        readonly property bool current: index === root.currentLine
                        readonly property int distance: Math.abs(index - Math.max(0, root.currentLine))
                        // Solo la línea activa construye sus palabras (ahorra memoria).
                        readonly property bool karaoke: current && modelData.words.length > 0

                        width: ListView.view.width
                        height: Math.max(lineText.implicitHeight,
                                         wordsLoader.item ? wordsLoader.height : 0) + 12

                        FontMetrics {
                            id: fm
                            font.family: Theme.fontUI
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }

                        // Texto base: da la altura y es la letra de las líneas inactivas.
                        Text {
                            id: lineText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 30
                            anchors.rightMargin: 30
                            anchors.verticalCenter: parent.verticalCenter
                            text: lineItem.modelData.text.length > 0 ? lineItem.modelData.text : "♪"
                            wrapMode: Text.WordWrap
                            horizontalAlignment: root.hasWords ? Text.AlignLeft : Text.AlignHCenter
                            font.family: Theme.fontUI
                            font.pixelSize: 14
                            font.weight: lineItem.current ? Font.Bold : Font.Normal
                            color: lineItem.current ? Theme.m3Primary : Theme.text
                            opacity: lineItem.karaoke ? 0
                                : (lineItem.current ? 1 : Math.max(0.2, 0.62 - lineItem.distance * 0.12))

                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        // Línea activa con palabras: relleno progresivo
                        Loader {
                            id: wordsLoader
                            active: lineItem.karaoke
                            anchors.left: parent.left
                            anchors.leftMargin: 30
                            anchors.verticalCenter: parent.verticalCenter

                            sourceComponent: Flow {
                                width: lineItem.width - 60

                                Repeater {
                                    model: lineItem.modelData.words

                                    delegate: Item {
                                        id: seg
                                        required property var modelData

                                        readonly property real p: Math.max(0, Math.min(1,
                                            (root.lyricsPos - modelData.t) / (modelData.e - modelData.t)))

                                        width: dim.implicitWidth + (modelData.space ? fm.advanceWidth(" ") : 0)
                                        height: dim.implicitHeight

                                        Text {
                                            id: dim
                                            text: seg.modelData.text
                                            color: Theme.text
                                            opacity: 0.45
                                            font.family: Theme.fontUI
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                        }

                                        Item {
                                            width: dim.implicitWidth * seg.p
                                            height: parent.height
                                            clip: true

                                            Text {
                                                text: seg.modelData.text
                                                color: Theme.m3Primary
                                                font.family: Theme.fontUI
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Notas a los lados: marcan la línea activa
                        Repeater {
                            model: 2
                            delegate: Text {
                                required property int index
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: index === 0 ? parent.left : undefined
                                anchors.right: index === 1 ? parent.right : undefined
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                text: "♪"
                                color: Theme.m3Primary
                                font.family: Theme.fontUI
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                opacity: lineItem.current ? 1 : 0
                                scale: lineItem.current ? 1 : 0.6

                                Behavior on opacity { NumberAnimation { duration: 220 } }
                                Behavior on scale {
                                    NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.canSeek
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.seekTo(lineItem.modelData.t / root.player.length)
                        }
                    }
                }

                // Letra sin marcas de tiempo: texto con desplazamiento
                Flickable {
                    id: lyricsFlick
                    visible: !root.hasSynced
                    anchors.fill: parent
                    anchors.margins: 16
                    contentWidth: width
                    contentHeight: lyricsLabel.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Text {
                        id: lyricsLabel
                        width: lyricsFlick.width
                        text: root.lyricsText
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: 13
                        lineHeight: 1.25
                        wrapMode: Text.WordWrap
                    }
                }

                Connections {
                    target: root
                    function onLyricsTextChanged() { lyricsFlick.contentY = 0; }
                }
            }
        }

        // ── Progreso + controles ──────────────────────────────────────
        Rectangle {
            id: controlsCard
            width: layout.width
            height: 100
            radius: 16
            color: Theme.chip
            visible: !root.compact

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                // Barra de progreso con seek
                Row {
                    id: progressRow
                    width: parent.width
                    height: 22
                    spacing: 10

                    Text {
                        id: timeLeft
                        width: 38
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.formatTime(seek.dragging && root.hasLength
                            ? seek.dragRatio * root.player.length
                            : root.displayPosition)
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 10
                    }

                    Item {
                        id: seek
                        width: progressRow.width - 2 * 38 - 2 * progressRow.spacing
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter

                        property bool dragging: false
                        property real dragRatio: 0
                        readonly property real shown: dragging ? dragRatio : root.progress
                        readonly property bool engaged: seekArea.containsMouse || dragging

                        // Onda tipo M3: la parte reproducida ondula (se aplana al
                        // pausar) y la restante es una línea recta.
                        Item {
                            id: track
                            anchors.fill: parent

                            property real phase: 0
                            property real amp: root.playing ? 1 : 0
                            readonly property color played: Theme.m3Primary
                            readonly property color rest: Theme.m3OutlineVariant

                            Behavior on amp {
                                NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                            }

                            onAmpChanged: wave.requestPaint()
                            onPlayedChanged: wave.requestPaint()
                            onRestChanged: wave.requestPaint()

                            // ~30 fps, solo mientras suena y el panel se ve
                            FrameAnimation {
                                id: tick
                                running: root.playing && root.visible
                                property int skip: 0
                                onTriggered: {
                                    track.phase += frameTime * 3.2;
                                    skip = (skip + 1) % 2;
                                    if (skip === 0) wave.requestPaint();
                                }
                            }

                            Connections {
                                target: seek
                                function onShownChanged() { wave.requestPaint(); }
                            }

                            Canvas {
                                id: wave
                                anchors.fill: parent

                                onWidthChanged: requestPaint()

                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();
                                    const w = width, h = height, mid = h / 2;
                                    const xp = Math.max(0, Math.min(w, w * seek.shown));
                                    const A = 3.2 * track.amp;
                                    const lambda = 20;
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";

                                    // Resto: línea recta
                                    ctx.strokeStyle = track.rest;
                                    ctx.lineWidth = 3;
                                    ctx.beginPath();
                                    ctx.moveTo(xp, mid);
                                    ctx.lineTo(w - 1.5, mid);
                                    ctx.stroke();

                                    // Reproducido: onda
                                    if (xp > 0.5) {
                                        ctx.strokeStyle = track.played;
                                        ctx.lineWidth = 3.5;
                                        ctx.beginPath();
                                        for (let x = 1.5; x <= xp; x += 1.5) {
                                            const env = Math.min(1, Math.max(0, (xp - x) / 14));
                                            const y = mid + A * env
                                                * Math.sin(x / lambda * 2 * Math.PI - track.phase);
                                            if (x === 1.5) ctx.moveTo(x, y);
                                            else ctx.lineTo(x, y);
                                        }
                                        ctx.lineTo(xp, mid);
                                        ctx.stroke();
                                    }
                                }
                            }
                        }

                        // Cursor en forma de píldora vertical
                        Rectangle {
                            width: 4
                            height: seek.engaged ? 20 : 16
                            radius: 2
                            color: Theme.m3Primary
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(seek.width - width,
                                seek.width * seek.shown - width / 2))

                            Behavior on height {
                                NumberAnimation { duration: 100 }
                            }
                        }

                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.canSeek
                            cursorShape: Qt.PointingHandCursor

                            function ratioAt(x) {
                                return Math.max(0, Math.min(1, x / width));
                            }

                            onPressed: mouse => {
                                seek.dragging = true;
                                seek.dragRatio = ratioAt(mouse.x);
                            }
                            onPositionChanged: mouse => {
                                if (pressed) seek.dragRatio = ratioAt(mouse.x);
                            }
                            onReleased: mouse => {
                                seek.dragRatio = ratioAt(mouse.x);
                                root.seekTo(seek.dragRatio);
                                seek.dragging = false;
                            }
                            onCanceled: seek.dragging = false
                        }
                    }

                    Text {
                        width: 38
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.hasLength ? root.formatTime(root.player.length) : "--:--"
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 10
                    }
                }

                // Botones
                Item {
                    width: parent.width
                    height: 48

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        MediaButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "shuffle"
                            diameter: 36
                            iconSize: 18
                            available: root.hasPlayer && root.player.shuffleSupported
                            active: root.shuffleOn
                            onClicked: root.toggleShuffle()
                        }

                        MediaButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "prev"
                            diameter: 40
                            available: root.hasPlayer && root.player.canGoPrevious
                            onClicked: root.player.previous()
                        }

                        MediaButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: root.playing ? "pause" : "play"
                            diameter: 48
                            iconSize: 22
                            filled: true
                            available: root.hasPlayer && root.player.canTogglePlaying
                            onClicked: root.player.togglePlaying()
                        }

                        MediaButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "next"
                            diameter: 40
                            available: root.hasPlayer && root.player.canGoNext
                            onClicked: root.player.next()
                        }

                        MediaButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "repeat"
                            badge: root.loopTrack ? "1" : ""
                            diameter: 36
                            iconSize: 18
                            available: root.loopSupported
                            active: root.loopOn
                            onClicked: root.cycleLoop()
                        }
                    }
                }
            }
        }

        // ── Espectro: el pie del panel en modo compacto ───────────────
        Spectrum {
            id: spectrum
            width: layout.width
            height: root.compact ? 64 : 0
            visible: root.compact
            active: root.compact
            playing: root.playing
        }
    }

    // ── Botón de modo compacto ────────────────────────────────────────
    // Tipo pantalla completa: al pulsarlo, el panel se queda con el álbum y
    // el espectro. Es discreto, pero siempre está ahí para volver.
    Item {
        id: compactButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 8
        width: 28
        height: 28
        z: 10

        opacity: compactHover.hovered ? 1.0 : 0.55

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.chip
            border.width: 1
            border.color: Theme.hairline
        }

        IconImage {
            anchors.centerIn: parent
            implicitSize: 16
            source: IconResolver.firstOf(root.compact
                ? ["window-restore-symbolic", "window-restore"]
                : ["view-fullscreen-symbolic", "view-fullscreen"])
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: compactHover.hovered
                    ? Theme.text
                    : Theme.textDim
            }
        }

        HoverHandler {
            id: compactHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: root.toggleCompact()
        }
    }
}

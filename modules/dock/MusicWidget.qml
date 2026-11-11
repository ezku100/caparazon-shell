import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../music/ArtUrls.js" as ArtUrls

// Widget compacto de reproducción dentro del dock.
// El cover gira solo mientras el reproductor está reproduciendo.
Item {
    id: root

    // Se emite al pulsar la carátula o el título: el dock abre con esto el
    // menú secundario en la categoría Música.
    signal activated()

    readonly property var players: Mpris.players && Mpris.players.values
        ? Mpris.players.values
        : []

    // Reproductores con algo que mostrar: sonando o con una pista cargada.
    readonly property var candidates: {
        const list = [];
        for (let i = 0; i < players.length; ++i) {
            const candidate = players[i];
            if (candidate && (candidate.isPlaying || candidate.trackTitle !== ""))
                list.push(candidate);
        }
        return list;
    }

    // Reproductor elegido a mano con la rueda; null = selección automática.
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

    // Cambia de reproductor con la rueda: step = 1 siguiente, -1 anterior.
    function cyclePlayer(step) {
        const count = candidates.length;
        if (count < 2)
            return;
        let index = candidates.indexOf(player);
        if (index < 0)
            index = count - 1;
        pinnedPlayer = candidates[(index + step + count) % count];
    }

    // Cambia cuando empieza o termina de sonar algún reproductor.
    readonly property string playingSignature: {
        let key = "";
        for (let i = 0; i < candidates.length; ++i) {
            if (candidates[i].isPlaying)
                key += i + ",";
        }
        return key;
    }

    // Si el elegido está en pausa y empieza a sonar otro, vuelve el modo
    // automático para que el widget siga lo que de verdad suena.
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

    // Si el reproductor elegido desaparece, se descarta la elección.
    onCandidatesChanged: {
        if (pinnedPlayer && candidates.indexOf(pinnedPlayer) === -1)
            pinnedPlayer = null;
    }

    // Sin pista ni reproducción activa no mostramos una tarjeta vacía.
    readonly property bool hasPlayer: player !== null
    // Ponlo en true para ver en la salida de quickshell qué URL de carátula
    // manda cada reproductor y si la imagen falla al cargar.
    readonly property bool debugArt: false

    // Carátulas a probar, en orden: la que manda el reproductor y, si es de
    // YouTube o la pestaña lo es, la miniatura del vídeo.
    readonly property var artCandidates: ArtUrls.artCandidates(player)

    // Posición dentro de artCandidates; avanza cuando una imagen falla.
    property int artIndex: 0
    readonly property string artKey: artCandidates.join("|")
    onArtKeyChanged: artIndex = 0

    readonly property string artUrl: artIndex < artCandidates.length
        ? artCandidates[artIndex]
        : ""
    readonly property string trackTitle: player ? (player.trackTitle || "") : ""
    readonly property string trackArtist: player
        ? (player.trackArtist || player.identity || "")
        : ""
    readonly property bool hasLength: player !== null
        && player.lengthSupported
        && player.length > 0
    readonly property real progress: hasLength
        ? Math.max(0, Math.min(1, displayPosition / player.length))
        : 0

    property real displayPosition: 0

    // En la columna vertical no cabe la tarjeta ancha: se queda la carátula y,
    // al pasar el puntero, la tarjeta se estira hacia abajo con los controles.
    property bool compact: false

    // Lo pone el dock: el puntero está encima (despliega) y la orientación.
    property bool hovering: false
    property bool expanded: false

    readonly property int cardHeight: 42
    readonly property int buttonsHeight: 76

    // Alto con los controles fuera: el dock usa `cardHeight` para calcular el
    // largo del cristal con la tarjeta plegada.
    readonly property int targetHeight: root.cardHeight
        + (root.compact && root.expanded ? root.buttonsHeight : 0)

    implicitWidth: compact ? 44 : (hasPlayer ? 256 : 0)
    implicitHeight: root.cardHeight
    // En columna los controles se guardan dentro de la tarjeta al plegarse.
    clip: root.compact
    // Se anima el alto real (no el implícito) para que la columna del dock
    // acompañe el despliegue fotograma a fotograma.
    height: root.targetHeight
    visible: hasPlayer

    Behavior on height {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    function syncPosition() {
        root.displayPosition = root.player
            ? Math.max(0, Number(root.player.position) || 0)
            : 0;
    }

    Component.onCompleted: syncPosition()

    onPlayerChanged: syncPosition()

    onArtUrlChanged: {
        if (debugArt)
            console.log("[MusicWidget] carátula de", player ? player.identity : "-", "→", artUrl);
    }

    // Rueda sobre el widget: cambia entre reproductores activos. Un clic de
    // rueda (120) cambia uno; los touchpads acumulan hasta llegar a ese valor.
    property real wheelAccum: 0

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            if (root.candidates.length < 2)
                return;
            if (root.wheelAccum * event.angleDelta.y < 0)
                root.wheelAccum = 0;
            root.wheelAccum += event.angleDelta.y;
            if (Math.abs(root.wheelAccum) >= 120) {
                // Rueda hacia arriba = anterior, hacia abajo = siguiente.
                root.cyclePlayer(root.wheelAccum > 0 ? -1 : 1);
                root.wheelAccum = 0;
            }
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.player !== null && root.player.isPlaying
        onTriggered: root.syncPosition()
    }

    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged() { root.syncPosition(); }
        function onLengthChanged() { root.syncPosition(); }
        function onTrackChanged() { root.syncPosition(); }
        function onIsPlayingChanged() { root.syncPosition(); }
        function onPlaybackStateChanged() { root.syncPosition(); }
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        // En columna la tarjeta abraza sólo la carátula; los controles van
        // sueltos sobre el cristal.
        height: root.compact ? root.cardHeight : parent.height
        radius: 12
        color: Theme.chip
    }

    Row {
        id: row
        anchors.fill: parent
        anchors.leftMargin: root.compact ? 3 : 8
        anchors.rightMargin: root.compact ? 3 : 8
        spacing: root.compact ? 0 : 7

        // Cover circular con anillo de progreso y giro lento. En horizontal
        // se centra en la fila; en columna va arriba porque los controles
        // se apilan debajo.
        Item {
            y: root.compact ? 2 : Math.round((parent.height - height) / 2)
            width: 38
            height: 38

            ClippingRectangle {
                anchors.centerIn: parent
                width: 34
                height: 34
                radius: width / 2
                color: Theme.chipHover

                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: root.artUrl
                    sourceSize.width: 34
                    sourceSize.height: 34
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // Los navegadores reutilizan la misma ruta temporal para
                    // pistas distintas; sin caché no se queda la carátula vieja.
                    cache: false
                    mipmap: true
                    visible: root.artUrl !== "" && status === Image.Ready

                    onStatusChanged: {
                        if (status !== Image.Error)
                            return;
                        if (root.debugArt)
                            console.log("[MusicWidget] no se pudo cargar:", root.artUrl);
                        // Probar la siguiente carátula de la lista, si hay.
                        if (root.artIndex < root.artCandidates.length - 1)
                            root.artIndex += 1;
                    }

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 20000
                        loops: Animation.Infinite
                        running: coverImage.visible
                            && root.player !== null
                            && root.player.isPlaying
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !root.artUrl || coverImage.status !== Image.Ready
                    text: "♪"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 20
                }
            }

            Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 2
                    strokeColor: Theme.hairline
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: 19
                        centerY: 19
                        radiusX: 17
                        radiusY: 17
                        startAngle: -90
                        sweepAngle: 360
                    }
                }

                ShapePath {
                    strokeWidth: 2
                    strokeColor: Theme.m3Primary
                    fillColor: "transparent"
                    capStyle: root.progress > 0
                        ? ShapePath.RoundCap
                        : ShapePath.FlatCap

                    PathAngleArc {
                        centerX: 19
                        centerY: 19
                        radiusX: 17
                        radiusY: 17
                        startAngle: -90
                        sweepAngle: 360 * root.progress
                    }
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.compact
            width: 120
            spacing: 1

            Text {
                width: parent.width
                text: root.trackTitle !== "" ? root.trackTitle : "Sin título"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                visible: root.trackArtist !== ""
                text: root.trackArtist
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 10
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Row {
            id: controls
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.compact
            width: 68
            spacing: 1

            MusicButton {
                icon: "media-skip-backward-symbolic"
                available: root.player !== null && root.player.canGoPrevious
                onActivated: if (root.player) root.player.previous()
            }

            MusicButton {
                icon: root.player && root.player.isPlaying
                    ? "media-playback-pause-symbolic"
                    : "media-playback-start-symbolic"
                available: root.player !== null && root.player.canTogglePlaying
                onActivated: if (root.player) root.player.togglePlaying()
            }

            MusicButton {
                icon: "media-skip-forward-symbolic"
                available: root.player !== null && root.player.canGoNext
                onActivated: if (root.player) root.player.next()
            }
        }
    }

    // Controles de la columna: mismos botones que en horizontal, apilados
    // bajo la carátula. Se pliegan con la tarjeta.
    Column {
        id: compactControls
        visible: root.compact
        enabled: root.expanded
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.cardHeight + 4
        spacing: 0
        opacity: root.expanded ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        MusicButton {
            icon: "media-skip-backward-symbolic"
            available: root.player !== null && root.player.canGoPrevious
            onActivated: if (root.player) root.player.previous()
        }

        MusicButton {
            icon: root.player && root.player.isPlaying
                ? "media-playback-pause-symbolic"
                : "media-playback-start-symbolic"
            available: root.player !== null && root.player.canTogglePlaying
            onActivated: if (root.player) root.player.togglePlaying()
        }

        MusicButton {
            icon: "media-skip-forward-symbolic"
            available: root.player !== null && root.player.canGoNext
            onActivated: if (root.player) root.player.next()
        }
    }

    // Clic en la carátula o el título para abrir el menú secundario (Música).
    // Queda declarado después de la fila para que esté por encima de la
    // carátula y el texto; su ancho se detiene antes de los controles para
    // que los botones sigan recibiendo sus clics con normalidad. En columna
    // no hay fila de controles que esquivar: cubre la carátula entera, que es
    // todo el alto de la tarjeta, y deja libres los botones de debajo.
    MouseArea {
        id: openMenuArea
        x: 0
        y: 0
        height: root.compact ? root.cardHeight : root.height
        width: root.compact
            ? root.width
            : Math.max(0, row.x + controls.x - row.spacing)
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    // Sólo observa: no consume clics ni hover de la carátula.
    HoverHandler {
        id: tileHover
        onHoveredChanged: root.hovering = hovered
    }
}

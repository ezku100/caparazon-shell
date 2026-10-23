import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import "../../theme"

// Widget compacto de reproducción dentro del dock.
// El cover gira solo mientras el reproductor está reproduciendo.
Item {
    id: root

    readonly property var players: Mpris.players && Mpris.players.values
        ? Mpris.players.values
        : []

    readonly property var player: {
        // Primero el reproductor que está sonando de verdad.
        for (let i = players.length - 1; i >= 0; --i) {
            const candidate = players[i];
            if (candidate && candidate.isPlaying)
                return candidate;
        }
        // Si no hay reproducción, conservamos una pista pausada con contenido.
        for (let i = players.length - 1; i >= 0; --i) {
            const candidate = players[i];
            if (candidate && candidate.trackTitle !== "")
                return candidate;
        }
        return null;
    }

    // Sin pista ni reproducción activa no mostramos una tarjeta vacía.
    readonly property bool hasPlayer: player !== null
    readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
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

    implicitWidth: hasPlayer ? 256 : 0
    implicitHeight: 42
    visible: hasPlayer

    function syncPosition() {
        root.displayPosition = root.player
            ? Math.max(0, Number(root.player.position) || 0)
            : 0;
    }

    Component.onCompleted: syncPosition()

    onPlayerChanged: syncPosition()

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
        anchors.fill: parent
        radius: 12
        color: Theme.chip
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 7

        // Cover circular con anillo de progreso y giro lento.
        Item {
            anchors.verticalCenter: parent.verticalCenter
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
                    mipmap: true
                    visible: root.artUrl !== "" && status === Image.Ready

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
            anchors.verticalCenter: parent.verticalCenter
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
}

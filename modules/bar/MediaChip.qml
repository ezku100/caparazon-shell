import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import "../../theme"

// Aviso efímero al cambiar de canción. Los reproductores MPRIS no mandan
// una notificación de escritorio por cada track, así que la barra escucha
// el metadata y muestra el cambio en el mismo grupo central.
Item {
    id: root

    // Vertical: sólo la carátula, con el ancho de la barra.
    property bool vertical: false

    readonly property var players: Mpris.players && Mpris.players.values
        ? Mpris.players.values
        : []

    readonly property var player: {
        for (let i = players.length - 1; i >= 0; --i) {
            const candidate = players[i];
            if (candidate && candidate.trackTitle !== "" && candidate.isPlaying)
                return candidate;
        }
        return players.length > 0 ? players[players.length - 1] : null;
    }

    property string lastTitle: ""
    property string shownTitle: ""
    property string shownArtist: ""
    property string shownArt: ""
    property bool active: false

    width: active
        ? (root.vertical ? Theme.barHeight : Math.min(320, content.implicitWidth + 16))
        : 0
    height: Theme.barHeight
    visible: active || width > 0.5

    // Mismo gesto que el aviso: fundido + "pop" con rebote + desliz de 6 px
    // desde el filo interior, todo desde un solo driver.
    property real presence: active ? 1 : 0
    Behavior on presence {
        NumberAnimation {
            duration: root.active ? 280 : 150
            easing.type: root.active ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.12
        }
    }
    opacity: presence
    scale: 0.84 + 0.16 * presence
    transformOrigin: Item.Center
    transform: Translate {
        x: (1 - root.presence) * (root.vertical ? -6 : 6)
    }

    // Hueco animado en la columna vertical: la carátula entra y el resto se
    // desliza en vez de dar un salto.
    property real slot: root.vertical && root.active ? 26 : 0
    Behavior on slot {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
    Layout.preferredWidth: root.vertical
        ? (root.active ? Theme.barHeight : 0)
        : Theme.barHeight
    Layout.preferredHeight: root.vertical ? root.slot : root.height

    Behavior on width {
        NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic }
    }

    Timer {
        id: hideTimer
        interval: 5000
        repeat: false
        onTriggered: root.active = false
    }

    function showTrack() {
        if (!player) {
            lastTitle = "";
            return;
        }

        const title = player.trackTitle || "";
        if (title === "" || title === lastTitle)
            return;

        lastTitle = title;
        shownTitle = title;
        shownArtist = player.trackArtist || player.identity || "";
        shownArt = player.trackArtUrl || "";
        active = true;
        hideTimer.restart();
    }

    onPlayerChanged: {
        lastTitle = player ? (player.trackTitle || "") : "";
        active = false;
        hideTimer.stop();
    }

    Connections {
        target: root.player
        function onTrackTitleChanged() { root.showTrack(); }
        function onMetadataChanged() { root.showTrack(); }
    }

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.vertical ? 26 : root.width
        height: root.vertical ? 26 : 30
        radius: root.vertical ? width / 2 : 10
        color: Theme.chip
        clip: true

        Row {
            id: content
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: root.vertical ? undefined : parent.left
            anchors.leftMargin: 8
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            spacing: 7

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                visible: root.shownArt !== ""
                source: root.shownArt
                sourceSize.width: 22
                sourceSize.height: 22
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.vertical
                width: Math.min(240, Math.max(title.implicitWidth, artist.implicitWidth))
                spacing: 0

                Text {
                    id: title
                    width: parent.width
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    text: root.shownTitle
                }

                Text {
                    id: artist
                    width: parent.width
                    visible: root.shownArtist !== ""
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    text: root.shownArtist
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: root.active = false
        }
    }
}

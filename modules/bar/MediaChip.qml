import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import "../../theme"

// Aviso efímero al cambiar de canción. Los reproductores MPRIS no mandan
// una notificación de escritorio por cada track, así que la barra escucha
// el metadata y muestra el cambio en el mismo grupo central.
Item {
    id: root

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

    width: active ? Math.min(320, content.implicitWidth + 16) : 0
    height: Theme.barHeight
    visible: active || width > 0.5
    opacity: active ? 1 : 0

    Behavior on width {
        NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
        NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
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
        width: root.width
        height: 30
        radius: 10
        color: Theme.chip
        clip: true

        Row {
            id: content
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
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

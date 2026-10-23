import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"

// Botón compacto para los controles del widget de música.
// No usa fondo permanente: solo ilumina el chip al pasar el cursor.
Item {
    id: root

    property string icon: ""
    property bool available: true

    signal activated()

    implicitWidth: 22
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: hover.hovered && root.available ? Theme.chipHover : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 14
        source: Quickshell.iconPath(root.icon, "media-playback-start-symbolic")

        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.available
                ? (hover.hovered ? Theme.text : Theme.textDim)
                : Theme.textDim
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.available
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.activated()
    }

    HoverHandler {
        id: hover
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    opacity: root.available ? 1.0 : 0.4
}

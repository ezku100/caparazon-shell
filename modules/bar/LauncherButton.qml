import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"

// Botón de aplicaciones de la barra. Quickshell 0.3 no expone atajos
// globales, así que el menú se abre desde aquí.
Item {
    id: root

    signal activated()

    implicitWidth: 28
    implicitHeight: 26

    Rectangle {
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: width / 2
        color: hover.hovered ? Qt.lighter(Theme.chipHover, 1.45) : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 19
        source: "file:///usr/share/pixmaps/pika-logo-duotone.svg"
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

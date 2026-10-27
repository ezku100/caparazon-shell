import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"

// Botón de la barra lateral del menú: sólo icono, como el resto del shell.
Item {
    id: root

    property string icon: "application-x-executable"
    property bool selected: false
    // false = se muestra el icono con sus colores originales (logo de la distro)
    property bool tint: true

    signal activated()

    implicitWidth: 36
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: root.selected
            ? Theme.m3Primary
            : (hover.hovered ? Theme.chipHover : "transparent")

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
        implicitSize: 18
        source: IconResolver.source(root.icon, "application-x-executable")
        layer.enabled: root.tint
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.selected
                ? Theme.m3OnPrimary
                : (hover.hovered ? Theme.text : Theme.textDim)
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

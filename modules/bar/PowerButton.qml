import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../icons"
import "../icons/BarIcons.js" as BarIcons
import "../../components"
import "../../theme"

// Botón de energía de la barra. El clic abre el menú central de sesión;
// las acciones reales viven en PowerMenu.qml.
HoverChip {
    id: root

    signal activated()

    implicitWidth: 28
    implicitHeight: 26

    // El fondo permanente es el círculo; el hover del HoverChip queda apagado.
    color: "transparent"

    // Mismo círculo de fondo que el selector de perfil de energía.
    Rectangle {
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: width / 2
        color: powerHover.hovered
            ? Qt.lighter(Theme.chipHover, 1.45)
            : Qt.lighter(Theme.chipHover, 1.3)

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler {
        id: powerHover
        cursorShape: Qt.PointingHandCursor
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 15
        source: IconResolver.firstOf(BarIcons.powerButtonNames())
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Theme.text
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

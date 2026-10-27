import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"

// Botón de aplicaciones de la barra. Quickshell 0.3 no expone atajos
// globales, así que el menú se abre desde aquí.
Item {
    id: root

    signal activated()

    // Logo de la distro: el especifico de PikaOS si el tema lo trae, si no el
    // archivo propio de PikaOS, y si tampoco esta, el logo generico del tema.
    readonly property string iconSource: {
        const themed = IconResolver.exactThemed([
            "distributor-logo-pikaos", "distributor-logo-pika-os",
            "pikaos-logo", "pikaos"]);
        if (themed.length > 0)
            return themed;
        const local = IconResolver.resolved("/usr/share/pixmaps/pika-logo-duotone.svg");
        if (local.length > 0)
            return local;
        return IconResolver.firstOf(["distributor-logo", "start-here"]);
    }

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
        source: root.iconSource
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

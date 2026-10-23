import Quickshell
import QtQuick
import "../../components"
import "../../theme"

// Apagado con confirmación en dos pasos: el primer clic arma el botón
// (chip rojo + "Apagar"), el segundo apaga. Se desarma solo a los 4 s.
HoverChip {
    id: root

    property bool armed: false

    // 28 normal; al armarse se ensancha para que quepa la etiqueta.
    implicitWidth: root.armed ? 82 : 28
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

    // Fondo de confirmación: el chip de hover queda debajo.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.m3ErrorContainer
        opacity: root.armed ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontIcon
            font.pixelSize: 15
            color: root.armed ? Theme.m3OnErrorContainer : Theme.text
            text: "\u{F0425}"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.armed
            font.family: Theme.fontUI
            font.pixelSize: Theme.fontPx
            color: Theme.m3OnErrorContainer
            text: "Apagar"
        }
    }

    Timer {
        id: disarmer
        interval: 4000
        onTriggered: root.armed = false
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (!root.armed) {
                root.armed = true;
                disarmer.restart();
            } else {
                disarmer.stop();
                root.armed = false;
                Quickshell.execDetached(["systemctl", "poweroff"]);
            }
        }
    }
}

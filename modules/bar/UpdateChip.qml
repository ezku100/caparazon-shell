import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"

// Aviso de actualización: aparece en la barra sólo mientras haya commits
// nuevos en el remoto. Al pulsarlo abre Configs, donde está el botón.
Item {
    id: root

    signal activated()

    visible: UpdateStatus.pending && UpdateStatus.state !== "updating"
    width: visible ? 26 : 0
    height: 26

    Rectangle {
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: width / 2
        color: hover.hovered
            ? Qt.lighter(Theme.m3Primary, 1.08)
            : Theme.m3Primary

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: IconResolver.firstOf([
            "software-update-available",
            "system-software-update",
            "system-update"
        ])
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Theme.m3OnPrimary
        }
    }

    Rectangle {
        width: 7
        height: 7
        radius: width / 2
        color: Theme.m3Error
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: 1
            topMargin: 1
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

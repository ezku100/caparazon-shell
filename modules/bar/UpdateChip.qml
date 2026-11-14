import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"

// Aviso de actualización. Vive en el grupo central, a la izquierda del
// reloj: al aparecer, el reloj se corre igual que cuando entra una
// notificación o un medio. Al pulsarlo abre Configs, donde está el botón.
Item {
    id: root

    signal activated()

    // Vertical: ocupa el ancho de la barra para quedar centrado en la columna.
    property bool vertical: false

    readonly property bool shown: UpdateStatus.pending
        && UpdateStatus.state !== "updating"

    width: shown ? (root.vertical ? Theme.barHeight : 26) : 0
    height: Theme.barHeight
    visible: shown || width > 0.5
    opacity: shown ? 1 : 0

    Behavior on width {
        NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
    }

    Behavior on opacity {
        NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
    }

    Item {
        id: visual
        anchors.centerIn: parent
        width: 26
        height: 26

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: hover.hovered
                ? Qt.lighter(Theme.m3Primary, 1.08)
                : Theme.m3Primary

            Behavior on color {
                ColorAnimation {
                    duration: Theme.durFast
                    easing.type: Easing.OutCubic
                }
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

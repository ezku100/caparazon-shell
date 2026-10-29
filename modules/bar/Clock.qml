import Quickshell
import QtQuick
import "../../theme"

// Reloj: hora grande + fecha. Sin fondo propio (lo pone el chip del padre).
Item {
    id: root

    property bool compact: false

    signal activated()

    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    readonly property var clockLocale: Qt.locale("es_MX")

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 9

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: 15
            font.weight: Font.DemiBold
            text: root.clockLocale.toString(clock.date, "h:mm AP")
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.compact
            width: 1
            height: 14
            color: Theme.hairline
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.compact
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 12
            text: root.clockLocale.toString(clock.date, "ddd d MMM")
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

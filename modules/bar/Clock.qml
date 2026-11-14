import Quickshell
import QtQuick
import "../../theme"

// Reloj: hora grande + fecha. Sin fondo propio (lo pone el chip del padre).
Item {
    id: root

    property bool compact: false
    // Vertical: hora, minutos y AM/PM se apilan en tres líneas dentro del
    // ancho de la barra.
    property bool vertical: false

    signal activated()

    implicitWidth: root.vertical ? Theme.barHeight : row.implicitWidth
    implicitHeight: root.vertical ? column.implicitHeight : Theme.barHeight

    readonly property var clockLocale: Qt.locale("es_MX")

    // Qt sólo interpreta "h" como hora de 12 h cuando va junto a "AP"; a
    // solas devuelve 24 h. Calculamos la hora 12 h a mano.
    readonly property int hour12: {
        const h = clock.date.getHours() % 12;
        return h === 0 ? 12 : h;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: row
        visible: !root.vertical
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

    // Vertical: hora, minutos y AM/PM apilados en ese orden, siempre en 12 h.
    Column {
        id: column
        visible: root.vertical
        anchors.centerIn: parent
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: 13
            font.weight: Font.DemiBold
            // Dos dígitos siempre: la columna no cambia de ancho al pasar
            // de las 9 a las 10 y la hora se lee alineada.
            text: String(root.hour12).padStart(2, "0")
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: 13
            font.weight: Font.DemiBold
            text: root.clockLocale.toString(clock.date, "mm")
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 9
            font.weight: Font.Medium
            text: root.clockLocale.toString(clock.date, "AP")
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

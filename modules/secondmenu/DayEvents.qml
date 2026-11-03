import Quickshell
import QtQuick
import "../../theme"

// Lista de eventos del día seleccionado: punto del color del calendario, hora
// a la izquierda, nombre del calendario a la derecha y título debajo.
Item {
    id: root

    property var events: []

    readonly property string emptyLabel: "Sin eventos este día"
    readonly property int count: root.events ? root.events.length : 0

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Theme.chip
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        model: root.events
        clip: true
        spacing: 10
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: entry
            required property var model

            readonly property bool allDay: entry.model.all_day === true
            readonly property string timeLabel: entry.allDay
                ? "Todo el día"
                : String(entry.model.start).substr(11, 5)

            width: list.width
            height: 40

            Rectangle {
                id: dot
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 4
                width: 8
                height: 8
                radius: 4
                color: entry.model.color || Theme.textDim
            }

            Text {
                anchors.left: dot.right
                anchors.leftMargin: 8
                anchors.top: parent.top
                width: 52
                text: entry.timeLabel
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                width: Math.min(parent.width * 0.45, implicitWidth)
                text: entry.model.calendar_name
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            Text {
                anchors.left: dot.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 16
                text: entry.model.name
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.count === 0
        text: root.emptyLabel
        color: Theme.textDim
        font.family: Theme.fontUI
        font.pixelSize: 11
    }
}

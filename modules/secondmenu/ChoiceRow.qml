import QtQuick
import "../../theme"

/*
  Fila binaria del panel de configs: rótulo, nota y punto de selección.
  La comparten el modo del dock y el modo día/noche.
*/
Rectangle {
    id: row

    required property string label
    required property string note
    required property bool current

    signal picked()

    width: parent ? parent.width : 0
    height: 52
    radius: 14
    color: row.current ? Theme.m3Primary : Theme.chip

    Behavior on color {
        ColorAnimation { duration: Theme.durFast }
    }

    Row {
        anchors {
            left: parent.left
            leftMargin: 14
            right: parent.right
            rightMargin: 14
            verticalCenter: parent.verticalCenter
        }
        spacing: 10

        Rectangle {
            width: 12
            height: 12
            radius: 6
            anchors.verticalCenter: parent.verticalCenter
            color: row.current ? Theme.m3OnPrimary : "transparent"
            border.width: row.current ? 0 : 1
            border.color: Theme.m3Outline
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 22
            spacing: 2

            Text {
                width: parent.width
                text: row.label
                color: row.current ? Theme.m3OnPrimary : Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: row.note
                color: row.current ? Theme.m3OnPrimary : Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.picked()
    }
}

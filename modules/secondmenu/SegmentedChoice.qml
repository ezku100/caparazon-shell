pragma ComponentBehavior: Bound

import QtQuick
import "../../theme"

/*
  Control segmentado: elige una opción entre dos o más en una sola fila.
  La usan el modo día/noche y el modo del dock.
*/
Row {
    id: control

    required property var options
    required property string value

    signal picked(string key)

    spacing: 4
    height: 44

    Repeater {
        model: control.options

        delegate: Rectangle {
            id: segment

            required property var modelData

            readonly property bool current: modelData.key === control.value
            readonly property real slot:
                (control.width - (control.options.length - 1) * control.spacing)
                    / control.options.length

            width: slot
            height: control.height
            radius: 12
            color: segment.current ? Theme.m3Primary : Theme.chip

            Behavior on color {
                ColorAnimation { duration: Theme.durFast }
            }

            Text {
                anchors.centerIn: parent
                text: segment.modelData.label
                color: segment.current ? Theme.m3OnPrimary : Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: control.picked(segment.modelData.key)
            }
        }
    }
}

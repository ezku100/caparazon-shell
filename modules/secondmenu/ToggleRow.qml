import QtQuick
import "../../theme"

// Fila con interruptor para opciones de sí/no del panel de configuración.
Item {
    id: root

    property string label: ""
    property string note: ""
    property bool value: false

    signal toggled()

    implicitHeight: 54
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Theme.chip

        Column {
            anchors {
                left: parent.left
                leftMargin: 14
                right: track.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 2

            Text {
                width: parent.width
                text: root.label
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.note
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: track

            anchors {
                right: parent.right
                rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            width: 40
            height: 22
            radius: height / 2
            color: root.value ? Theme.m3Primary : Theme.chipHover

            Behavior on color {
                ColorAnimation {
                    duration: Theme.durFast
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                width: 16
                height: 16
                radius: width / 2
                y: (parent.height - height) / 2
                x: root.value ? parent.width - width - 3 : 3
                color: root.value ? Theme.m3OnPrimary : Theme.textDim

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.durFast
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.durFast
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }
}

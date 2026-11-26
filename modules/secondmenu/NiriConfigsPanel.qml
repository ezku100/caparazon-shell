import QtQuick
import "../../theme"

Flickable {
    id: root

    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
        id: body

        width: root.width
        spacing: 10

        Row {
            id: header

            width: parent.width
            height: 22

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Niri configs"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
        }

        Text {
            width: parent.width
            text: "Monitores"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
        }

        Item {
            id: monitorsHost

            width: parent.width
            height: monitorsLoader.item ? monitorsLoader.item.implicitHeight : 0

            Loader {
                id: monitorsLoader

                anchors.fill: parent
                sourceComponent: monitorComponent
            }
        }

        Text {
            width: parent.width
            text: "Teclado"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
        }

        Item {
            id: keyboardHost

            width: parent.width
            height: keyboardLoader.item ? keyboardLoader.item.implicitHeight : 0

            Loader {
                id: keyboardLoader

                anchors.fill: parent
                sourceComponent: keyboardComponent
            }
        }
    }

    Component {
        id: monitorComponent

        MonitorsPanel {
            anchors.fill: parent
        }
    }

    Component {
        id: keyboardComponent

        KeyboardLayoutPanel {
            anchors.fill: parent
        }
    }
}

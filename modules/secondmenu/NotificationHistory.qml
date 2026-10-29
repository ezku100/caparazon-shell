import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"

// Historial de notificaciones del menú secundario, de la más nueva a la más
// vieja. El modelo lo mantiene la shell (ListModel notificationHistory).
Item {
    id: root

    property var model: null

    readonly property int count: model ? model.count : 0

    function relativeStamp(stamp) {
        const diff = Math.max(0, Date.now() - Number(stamp || 0));
        const mins = Math.floor(diff / 60000);
        if (mins < 1)
            return "ahora";
        if (mins < 60)
            return mins + " min";
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return hours + " h";
        return Math.floor(hours / 24) + " d";
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Theme.chip
    }

    Column {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Text {
            id: title
            text: "Notificaciones"
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Item {
            id: listArea
            width: parent.width
            height: content.height - title.height - content.spacing

            ListView {
                id: list
                anchors.fill: parent
                model: root.model
                clip: true
                spacing: 10
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    width: list.width
                    height: 40

                    Row {
                        id: entry
                        anchors.fill: parent
                        spacing: 8

                        Image {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            width: 16
                            height: 16
                            source: IconResolver.resolved(appIcon)
                            fillMode: Image.PreserveAspectFit
                            visible: source !== ""
                        }

                        Column {
                            width: entry.width - 24
                            spacing: 1

                            Item {
                                width: parent.width
                                height: 13

                                Text {
                                    width: parent.width - 34
                                    text: appName.length > 0 ? appName : "Sistema"
                                    color: Theme.textDim
                                    font.family: Theme.fontUI
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    anchors.right: parent.right
                                    text: root.relativeStamp(stamp)
                                    color: Theme.textDim
                                    font.family: Theme.fontUI
                                    font.pixelSize: 9
                                }
                            }

                            Text {
                                width: parent.width
                                text: summary.length > 0 ? summary : body
                                color: Theme.text
                                font.family: Theme.fontUI
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Text {
                                width: parent.width
                                visible: summary.length > 0 && body.length > 0
                                text: body
                                color: Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.count === 0
                text: "Sin notificaciones"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
            }
        }
    }
}

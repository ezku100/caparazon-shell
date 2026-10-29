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

    signal notificationActivated(string entry)

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

        Item {
            id: titleRow
            width: parent.width
            height: 14

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Notificaciones"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Item {
                id: clearButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: clearLabel.width + 12
                height: 16
                visible: root.count > 0

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: clearHover.hovered ? Theme.chipHover : "transparent"
                }

                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "Limpiar"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                HoverHandler {
                    id: clearHover
                    cursorShape: Qt.PointingHandCursor
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        if (root.model)
                            root.model.clear();
                    }
                }
            }
        }

        Item {
            id: listArea
            width: parent.width
            height: content.height - titleRow.height - content.spacing

            ListView {
                id: list
                anchors.fill: parent
                model: root.model
                clip: true
                spacing: 10
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: entryItem

                    readonly property string desktopEntryId:
                        (typeof desktopEntry === "undefined" || !desktopEntry)
                            ? "" : String(desktopEntry)

                    width: list.width
                    height: 40

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: entryHover.hovered && entryItem.desktopEntryId.length > 0
                            ? Theme.chipHover : "transparent"
                    }

                    Row {
                        id: entry
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
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

                    HoverHandler {
                        id: entryHover
                        cursorShape: entryItem.desktopEntryId.length > 0
                            ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        enabled: entryItem.desktopEntryId.length > 0
                        onClicked: root.notificationActivated(entryItem.desktopEntryId)
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

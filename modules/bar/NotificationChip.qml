import Quickshell
import QtQuick
import "../../theme"

// Notificación activa más reciente. Vive al lado del reloj dentro del
// grupo centrado: cuando aparece, el reloj se desplaza hacia escritorios
// y el chip ocupa el espacio de la derecha, manteniendo el conjunto al centro.
Item {
    id: root

    property var server: null

    readonly property var values: server && server.trackedNotifications
        ? server.trackedNotifications.values
        : []
    readonly property var notification: values && values.length > 0
        ? values[values.length - 1]
        : null
    readonly property bool active: notification !== null

    readonly property string iconSource: {
        if (!notification || !notification.appIcon)
            return "";
        const path = Quickshell.iconPath(notification.appIcon, true);
        return path !== "" ? path : notification.appIcon;
    }

    width: active ? Math.min(260, content.implicitWidth + 16) : 0
    height: Theme.barHeight
    visible: active || width > 0.5
    opacity: active ? 1 : 0

    Behavior on width {
        NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic }
    }

    // Quickshell no expira solo: trackedNotifications conserva la instancia.
    // El expire_timeout de D-Bus viene en milisegundos; si no viene, 5 s.
    Timer {
        id: expireTimer
        repeat: false
        onTriggered: if (root.notification)
            root.notification.dismiss()
    }

    onNotificationChanged: {
        if (!notification) {
            expireTimer.stop();
            return;
        }
        const timeout = notification.expireTimeout;
        expireTimer.interval = timeout > 0 ? Math.round(timeout) : 5000;
        expireTimer.restart();
    }
    Behavior on opacity {
        NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        width: root.width
        height: 28
        radius: 9
        color: Theme.chip
        clip: true

        Row {
            id: content
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            spacing: 7

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                visible: root.iconSource !== ""
                source: root.iconSource
                sourceSize.width: 16
                sourceSize.height: 16
                fillMode: Image.PreserveAspectFit
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(216, Math.max(summary.implicitWidth, body.implicitWidth))
                spacing: 0

                Text {
                    id: summary
                    width: parent.width
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: root.notification
                        ? (root.notification.summary
                            || root.notification.body
                            || root.notification.appName
                            || "Notificación")
                        : ""
                }

                Text {
                    id: body
                    width: parent.width
                    visible: root.notification
                        && root.notification.summary !== ""
                        && root.notification.body !== ""
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 8
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: root.notification ? root.notification.body : ""
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: if (root.notification)
                root.notification.dismiss()
        }
    }
}

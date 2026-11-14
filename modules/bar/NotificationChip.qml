import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../icons"

// Notificación activa más reciente. Vive al lado del reloj dentro del
// grupo centrado: cuando aparece, el reloj se desplaza hacia escritorios
// y el chip ocupa el espacio de la derecha, manteniendo el conjunto al centro.
Item {
    id: root

    property var server: null
    // Vertical: sólo el icono, con el ancho de la barra.
    property bool vertical: false

    readonly property var values: server && server.trackedNotifications
        ? server.trackedNotifications.values
        : []
    readonly property var notification: values && values.length > 0
        ? values[values.length - 1]
        : null
    readonly property bool active: notification !== null

    // Icono de la app que lanzó el aviso; si no trae uno, el genérico de
    // notificación (firstOf nunca devuelve "" porque cae al icono genérico).
    readonly property string iconSource: {
        if (!notification)
            return "";
        const appIcon = IconResolver.resolved(notification.appIcon);
        if (appIcon.length > 0)
            return appIcon;
        return IconResolver.firstOf([
            "notifications-symbolic",
            "dialog-information-symbolic",
            "preferences-desktop-notification"
        ]);
    }

    width: active
        ? (root.vertical ? Theme.barHeight : Math.min(260, content.implicitWidth + 16))
        : 0
    height: Theme.barHeight
    visible: active || width > 0.5

    // 0→1 gobierna entrada y salida: fundido, un "pop" corto (escala con
    // rebote al entrar) y un desliz de 6 px desde el filo interior. Un solo
    // driver mantiene el gesto acompasado en vez de tres animaciones sueltas.
    property real presence: active ? 1 : 0
    Behavior on presence {
        NumberAnimation {
            duration: root.active ? 280 : 150
            easing.type: root.active ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.12
        }
    }
    opacity: presence
    scale: 0.84 + 0.16 * presence
    transformOrigin: Item.Center
    transform: Translate {
        x: (1 - root.presence) * (root.vertical ? -6 : 6)
    }

    // Hueco que ocupa en la columna vertical. Se anima para que al entrar o
    // salir el aviso el reloj y la carátula se deslicen, en vez de saltar.
    property real slot: root.vertical && root.active ? 26 : 0
    Behavior on slot {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
    // El ColumnLayout manda el tamaño: sin preferidos usa implicitWidth (0) y
    // el chip se dibuja fuera de la barra; sin aviso no debe reservar hueco.
    Layout.preferredWidth: root.vertical
        ? (root.active ? Theme.barHeight : 0)
        : Theme.barHeight
    Layout.preferredHeight: root.vertical ? root.slot : root.height

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

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.vertical ? 26 : root.width
        height: root.vertical ? 26 : 28
        radius: root.vertical ? width / 2 : 9
        color: Theme.chip
        clip: true

        Row {
            id: content
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: root.vertical ? undefined : parent.left
            anchors.leftMargin: 8
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
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
                visible: !root.vertical
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

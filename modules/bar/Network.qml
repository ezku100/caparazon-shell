import Quickshell
import Quickshell.Networking
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"

// Indicador de red (NetworkManager vía Quickshell.Networking).
Item {
    id: root

    implicitWidth: 28
    implicitHeight: 26

    readonly property string iconDir: "file:///usr/share/icons/Papirus/22x22/panel/"

    // Networking.devices es un ObjectModel; hay que usar .values.
    readonly property var devs: Networking.devices ? Networking.devices.values : []

    readonly property bool hasWired: {
        for (const dev of root.devs) {
            if (dev.connected && dev.type === DeviceType.Wired)
                return true;
        }
        return false;
    }

    readonly property bool hasWifi: {
        for (const dev of root.devs) {
            if (dev.connected && dev.type === DeviceType.Wifi)
                return true;
        }
        return false;
    }

    // Si ambas están conectadas, Ethernet tiene prioridad.
    readonly property string kind: root.hasWired ? "wired"
        : root.hasWifi ? "wifi"
        : "off"

    // Mismo círculo de fondo que el selector de perfil de energía.
    Rectangle {
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: width / 2
        color: hover.hovered
            ? Qt.lighter(Theme.chipHover, 1.45)
            : Qt.lighter(Theme.chipHover, 1.3)

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: root.iconDir + (root.kind === "wired" ? "network-wired.svg"
            : root.kind === "wifi" ? "network-wireless-connected.svg"
            : "network-wireless-disconnected.svg")
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.kind === "off" ? Theme.textDim : Theme.text
        }
    }
}

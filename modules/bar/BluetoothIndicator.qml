import Quickshell
import Quickshell.Bluetooth
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"

// Indicador de Bluetooth. Sólo ocupa espacio cuando BlueZ reconoce al menos
// un adaptador; si no hay dongle o no se detecta, desaparece por completo.
// Clic: enciende/apaga el adaptador.
Item {
    id: root

    readonly property string iconDir: "file:///usr/share/icons/Papirus/22x22/panel/"
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool active: root.adapter !== null
        && root.adapter.enabled
        && root.adapter.state === BluetoothAdapterState.Enabled

    implicitWidth: 28
    implicitHeight: 26
    visible: root.available

    // Mismo círculo de fondo que el selector de perfil de energía.
    Rectangle {
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: width / 2
        color: root.active
            ? (hover.hovered
                ? Qt.lighter(Theme.m3Primary, 1.08)
                : Theme.m3Primary)
            : (hover.hovered
                ? Qt.lighter(Theme.chipHover, 1.45)
                : Qt.lighter(Theme.chipHover, 1.3))

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
        source: root.active
            ? root.iconDir + "bluetooth-active.svg"
            : root.iconDir + "bluetooth-disabled.svg"
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.active ? Theme.m3OnPrimary : Theme.textDim
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.adapter)
                root.adapter.enabled = !root.adapter.enabled;
        }
    }
}

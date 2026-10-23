import QtQuick
import "../../theme"

// CPU, RAM, GPU, swap/zram y red.
// Los valores llegan del ResourceMonitorService global.
Item {
    id: root

    property int cpu: 0
    property int ram: 0
    property int gpu: 0
    property int swap: 0
    property int network: 0
    property string networkIcon: "network-wired"

    readonly property string papirusPanel: "file:///usr/share/icons/Papirus/22x22/panel/"
    readonly property string networkSource: root.papirusPanel + "network-transmit-receive.svg"

    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        ResourceRing {
            label: "CPU"
            value: root.cpu
            iconSource: root.papirusPanel + "indicator-sensors-cpu.svg"
        }

        ResourceRing {
            label: "RAM"
            value: root.ram
            iconSource: root.papirusPanel + "indicator-sensors-memory.svg"
        }

        ResourceRing {
            label: "GPU"
            value: root.gpu
            iconSource: root.papirusPanel + "indicator-sensors-gpu.svg"
        }

        ResourceRing {
            label: "Swap"
            value: root.swap
            iconSource: root.papirusPanel + "drive-harddisk.svg"
        }

        ResourceRing {
            label: "Red"
            value: root.network
            iconSource: root.networkSource
        }
    }
}

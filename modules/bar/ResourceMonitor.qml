import QtQuick
import "../../theme"
import "../icons"

// CPU, RAM, GPU, swap/zram y red.
// Los valores llegan del ResourceMonitorService global.
Item {
    id: root

    property int cpu: 0
    property int ram: 0
    property int gpu: 0
    property int swap: 0
    property int network: 0

    readonly property string networkSource: IconResolver.firstOf([
        "network-transmit-receive", "network-wired", "network-wireless"])

    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        ResourceRing {
            label: "CPU"
            value: root.cpu
            iconSource: IconResolver.firstOf([
                "cpu", "indicator-sensors-cpu", "utilities-system-monitor", "computer"])
        }

        ResourceRing {
            label: "RAM"
            value: root.ram
            iconSource: IconResolver.firstOf([
                "memory", "indicator-sensors-memory", "media-flash", "media-floppy"])
        }

        ResourceRing {
            label: "GPU"
            value: root.gpu
            iconSource: IconResolver.firstOf([
                "video-card", "indicator-sensors-gpu", "video-display", "computer"])
        }

        ResourceRing {
            label: "Swap"
            value: root.swap
            iconSource: IconResolver.firstOf([
                "drive-harddisk", "drive-harddisk-solidstate", "media-floppy"])
        }

        ResourceRing {
            label: "Red"
            value: root.network
            iconSource: root.networkSource
        }
    }
}

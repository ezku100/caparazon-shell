import Quickshell
import Quickshell.Widgets
import QtQuick
import "../../theme"
import "../icons"

// CPU, RAM, GPU, swap/zram y red.
// Los valores llegan del ResourceMonitorService global y cada anillo se
// puede apagar desde el panel "Monitor del sistema" del submenú.
Item {
    id: root

    property int cpu: 0
    property int ram: 0
    property int gpu: 0
    property int swap: 0
    property int network: 0
    property int temperature: 0

    // Servicio global: guarda qué medidores están apagados para que el
    // estado sea el mismo en todas las barras.
    property var resources: null

    // Barra abajo: los globos de ayuda de los anillos abren hacia arriba.
    property bool tipAbove: false

    // Barra vertical: los anillos se apilan en columna.
    property bool vertical: false

    // Barra pegada al borde izquierdo: los globos salen hacia la derecha.
    property bool barAtLeft: false

    // Al pulsar cualquier anillo se abre la categoría del monitor del
    // sistema en el menú secundario.
    signal activated()

    readonly property string networkSource: IconResolver.firstOf([
        "network-transmit-receive", "network-wired", "network-wireless"])

    function isHidden(key) {
        return resources ? resources.isHidden(key) : false;
    }

    implicitWidth: grid.implicitWidth
    implicitHeight: root.vertical ? grid.implicitHeight : Theme.barHeight

    Grid {
        id: grid
        // Una fila con los anillos activos; uno por fila en vertical.
        columns: root.vertical ? 1 : 6
        flow: Grid.LeftToRight
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        columnSpacing: 4
        rowSpacing: 4

        ResourceRing {
            tipAbove: root.tipAbove
            vertical: root.vertical
            barAtLeft: root.barAtLeft
            label: "CPU"
            value: root.cpu
            visible: !root.isHidden("cpu")
            iconSource: IconResolver.firstOf([
                "cpu", "indicator-sensors-cpu", "utilities-system-monitor", "computer"])
        }

        ResourceRing {
            tipAbove: root.tipAbove
            vertical: root.vertical
            barAtLeft: root.barAtLeft
            label: "RAM"
            value: root.ram
            visible: !root.isHidden("ram")
            iconSource: IconResolver.firstOf([
                "memory", "indicator-sensors-memory", "media-flash", "media-floppy"])
        }

        ResourceRing {
            tipAbove: root.tipAbove
            vertical: root.vertical
            barAtLeft: root.barAtLeft
            label: "GPU"
            value: root.gpu
            visible: !root.isHidden("gpu")
            iconSource: IconResolver.firstOf([
                "video-card", "indicator-sensors-gpu", "video-display", "computer"])
        }

        ResourceRing {
            tipAbove: root.tipAbove
            vertical: root.vertical
            barAtLeft: root.barAtLeft
            label: "Swap"
            value: root.swap
            visible: !root.isHidden("swap")
            iconSource: IconResolver.firstOf([
                "drive-harddisk", "drive-harddisk-solidstate", "media-floppy"])
        }

        ResourceRing {
            tipAbove: root.tipAbove
            vertical: root.vertical
            barAtLeft: root.barAtLeft
            label: "Red"
            value: root.network
            visible: !root.isHidden("network")
            iconSource: root.networkSource
        }

        ResourceRing {
            tipAbove: root.tipAbove
            vertical: root.vertical
            barAtLeft: root.barAtLeft
            label: "Temp"
            value: root.temperature
            unit: "°C"
            visible: !root.isHidden("temp")
            iconSource: IconResolver.firstOf([
                "temperature", "thermometer", "indicator-sensors-temperature", "weather-clear"])
        }
    }

    // Capa de clic por encima de los anillos: los anillos sólo muestran el
    // globo de ayuda, así que aquí llega el clic que abre el monitor.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

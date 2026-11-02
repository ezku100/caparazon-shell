import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../../theme"
import "../icons"

/*
  Categoría "Monitor del sistema" del menú secundario.

  Un único gráfico grande con selector de métrica (CPU, RAM, GPU, Swap,
  red y temperatura), al estilo del Mission Center de GNOME: la pestaña
  elegida manda y debajo van actual, máximo, mínimo y media de la ventana
  muestreada.

  Cada muestra es una fila [cpu, ram, gpu, swap, red, temperatura] que el
  ResourceMonitorService guarda con una muestra por segundo.
*/
Item {
    id: root

    property int cpu: 0
    property int ram: 0
    property int gpu: 0
    property int swap: 0
    property int network: 0
    property int temperature: 0
    property var samples: []
    property var resources: null

    // Métricas que tienen anillo en la barra: aquí se apagan y se encienden.
    readonly property var barMeters: [
        { key: "cpu", label: "CPU" },
        { key: "ram", label: "RAM" },
        { key: "gpu", label: "GPU" },
        { key: "swap", label: "Swap" },
        { key: "network", label: "Red" }
    ]

    function isHidden(key) {
        return resources ? resources.isHidden(key) : false;
    }

    function toggleMeter(key) {
        if (resources)
            resources.toggleMeter(key);
    }

    // Métrica elegida en el selector. El orden coincide con el de las
    // muestras que entrega el servicio.
    property int selectedIndex: 0

    readonly property var metrics: [
        {
            label: "CPU",
            unit: "%",
            index: 0,
            source: IconResolver.firstOf([
                "cpu", "indicator-sensors-cpu", "utilities-system-monitor", "computer"])
        },
        {
            label: "RAM",
            unit: "%",
            index: 1,
            source: IconResolver.firstOf([
                "memory", "indicator-sensors-memory", "media-flash", "media-floppy"])
        },
        {
            label: "GPU",
            unit: "%",
            index: 2,
            source: IconResolver.firstOf([
                "video-card", "indicator-sensors-gpu", "video-display", "computer"])
        },
        {
            label: "Swap",
            unit: "%",
            index: 3,
            source: IconResolver.firstOf([
                "drive-harddisk", "drive-harddisk-solidstate", "media-floppy"])
        },
        {
            label: "Red",
            unit: "%",
            index: 4,
            source: IconResolver.firstOf([
                "network-transmit-receive", "network-wired", "network-wireless"])
        },
        {
            label: "Temp",
            unit: "°C",
            index: 5,
            source: IconResolver.firstOf([
                "temperature", "thermometer", "utilities-system-monitor", "computer"])
        }
    ]

    readonly property var metric: root.metrics[root.selectedIndex]
    readonly property bool isThermal: root.selectedIndex === 5

    // Serie de la métrica elegida: los valores de las muestras.
    readonly property var series: {
        const rows = root.samples || [];
        const index = root.metric.index;
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const row = rows[i];
            if (row && row.length > index)
                out.push(Number(row[index]) || 0);
        }
        return out;
    }

    readonly property real seriesMax: {
        let max = 0;
        for (let i = 0; i < root.series.length; i++)
            max = Math.max(max, root.series[i]);
        return max;
    }

    readonly property real seriesMin: {
        let min = Infinity;
        for (let i = 0; i < root.series.length; i++)
            min = Math.min(min, root.series[i]);
        return root.series.length ? min : 0;
    }

    readonly property real seriesAvg: {
        if (root.series.length === 0)
            return 0;
        let sum = 0;
        for (let i = 0; i < root.series.length; i++)
            sum += root.series[i];
        return sum / root.series.length;
    }

    // Valor en vivo de la métrica elegida (la última muestra puede tardar
    // un instante en llegar).
    readonly property real currentValue: {
        switch (root.selectedIndex) {
        case 0: return root.cpu;
        case 1: return root.ram;
        case 2: return root.gpu;
        case 3: return root.swap;
        case 4: return root.network;
        default: return root.temperature;
        }
    }

    // Escala del eje: los porcentajes van de 0 a 100; la temperatura se
    // ajusta a los valores medidos para que la curva llene el gráfico.
    readonly property real axisMin: {
        if (!root.isThermal)
            return 0;
        const base = Math.max(0, Math.floor(root.seriesMin - 5));
        return base;
    }

    readonly property real axisMax: {
        if (!root.isThermal)
            return 100;
        const span = Math.max(20, root.seriesMax - root.axisMin);
        return Math.ceil((root.seriesMax + 5) / 10) * 10;
    }

    function formatValue(value) {
        return Math.round(value) + root.metric.unit;
    }

    Column {
        id: layout
        anchors.fill: parent
        spacing: 12

        Row {
            id: header
            width: parent.width

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Monitor del sistema"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                text: root.series.length > 1
                    ? root.series.length + " muestras"
                    : "recopilando datos"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 12
            }
        }

        // Selector de métrica: cada pestaña lleva icono, nombre y valor.
        Row {
            id: selector
            width: parent.width
            spacing: 8

            Repeater {
                model: root.metrics

                delegate: Rectangle {
                    id: tab

                    required property int index
                    required property var modelData

                    readonly property bool selected: root.selectedIndex === tab.index

                    width: Math.floor((selector.width - (selector.spacing * 5)) / 6)
                    height: 46
                    radius: 14
                    color: tab.selected ? Theme.m3Primary : Theme.chip

                    Behavior on color {
                        ColorAnimation { duration: Theme.durFast }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        IconImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitSize: 14
                            source: tab.modelData.source
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: tab.selected
                                    ? Theme.m3OnPrimary
                                    : Theme.textDim
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tab.modelData.label
                            color: tab.selected ? Theme.m3OnPrimary : Theme.textDim
                            font.family: Theme.fontUI
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                switch (tab.index) {
                                case 0: return Math.round(root.cpu) + "%";
                                case 1: return Math.round(root.ram) + "%";
                                case 2: return Math.round(root.gpu) + "%";
                                case 3: return Math.round(root.swap) + "%";
                                case 4: return Math.round(root.network) + "%";
                                default: return Math.round(root.temperature) + "°C";
                                }
                            }
                            color: tab.selected ? Theme.m3OnPrimary : Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedIndex = tab.index
                    }
                }
            }
        }

        // Gráfico grande de la métrica elegida.
        Rectangle {
            id: chartCard
            width: parent.width
            height: Math.max(150, layout.height - header.height - selector.height
                - barToggles.height - stats.height - (layout.spacing * 4))
            radius: 16
            color: Theme.chip

            Row {
                id: chartHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14

                IconImage {
                    id: chartIcon
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 16
                    source: root.metric.source
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.textDim
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: chartIcon.right
                    anchors.leftMargin: 8
                    text: root.metric.label
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 13
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: root.formatValue(root.currentValue)
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                }
            }

            Item {
                id: chartArea
                anchors.fill: parent
                anchors.topMargin: 44
                anchors.bottomMargin: 22
                anchors.leftMargin: 14
                anchors.rightMargin: 46

                // Curva y área bajo la curva en un solo motor de trazado que
                // ya usan los anillos de la barra.
                readonly property string linePath: chartArea.buildPath(false)
                readonly property string areaPath: chartArea.buildPath(true)

                function buildPath(close) {
                    const data = root.series;
                    const w = chartArea.width;
                    const h = chartArea.height;
                    if (data.length < 2 || w <= 0 || h <= 0)
                        return "";

                    const span = Math.max(1, root.axisMax - root.axisMin);
                    const step = w / (data.length - 1);
                    let path = "";

                    for (let i = 0; i < data.length; i++) {
                        const value = Math.max(root.axisMin,
                            Math.min(root.axisMax, data[i]));
                        const x = i * step;
                        const y = h - ((value - root.axisMin) / span) * h;
                        path += (i === 0 ? "M" : " L") + x.toFixed(2) + ","
                            + y.toFixed(2);
                    }

                    if (close)
                        path += " L" + w.toFixed(2) + "," + h.toFixed(2)
                            + " L0," + h.toFixed(2) + " Z";
                    return path;
                }

                Shape {
                    anchors.fill: parent
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: Qt.alpha(Theme.m3Primary, 0.22)
                        strokeColor: "transparent"

                        PathSvg {
                            path: chartArea.areaPath
                        }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Theme.m3Primary
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: chartArea.linePath
                        }
                    }
                }

                // Cuadrícula con las marcas del eje.
                Repeater {
                    model: 5

                    delegate: Rectangle {
                        required property int index

                        width: chartArea.width
                        height: 1
                        y: chartArea.height * (1 - index / 4) - 0.5
                        color: Theme.hairline
                    }
                }

                // Punto de la última muestra.
                Rectangle {
                    id: lastDot
                    width: 7
                    height: 7
                    radius: width / 2
                    color: Theme.m3Primary
                    visible: root.series.length > 1

                    readonly property real span: Math.max(1,
                        root.axisMax - root.axisMin)
                    readonly property real value: root.series.length
                        ? root.series[root.series.length - 1]
                        : 0

                    x: chartArea.width - width / 2
                    y: chartArea.height
                        - ((Math.max(root.axisMin, Math.min(root.axisMax, value))
                            - root.axisMin) / span) * chartArea.height
                        - height / 2
                }
            }

            // Marcas del eje vertical.
            Item {
                id: axisLabels
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.top: chartArea.top
                anchors.bottom: chartArea.bottom
                width: 34

                Repeater {
                    model: 5

                    delegate: Text {
                        required property int index

                        anchors.right: parent.right
                        y: (axisLabels.height - implicitHeight) * (1 - index / 4)
                        text: Math.round(root.axisMin
                            + (root.axisMax - root.axisMin) * (index / 4))
                            + root.metric.unit
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 10
                    }
                }
            }

            // Marcas de tiempo en el borde inferior.
            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 14
                anchors.bottomMargin: 6
                text: "hace 2 min"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 10
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 14
                anchors.bottomMargin: 6
                text: "ahora"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 10
            }
        }

        // Interruptores de los anillos de la barra.
        Rectangle {
            id: barToggles
            width: parent.width
            height: 46
            radius: 14
            color: Theme.chip

            Row {
                id: toggleRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "En la barra"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 12
                }

                Repeater {
                    model: root.barMeters

                    delegate: Rectangle {
                        id: toggle

                        required property var modelData

                        readonly property bool shown: !root.isHidden(toggle.modelData.key)

                        width: toggleContent.implicitWidth + 22
                        height: 28
                        radius: 14
                        color: toggle.shown ? Theme.chipHover : "transparent"
                        border.width: 1
                        border.color: Theme.hairline

                        Row {
                            id: toggleContent
                            anchors.centerIn: parent
                            spacing: 6

                            // Punto de estado: relleno si el anillo está en
                            // la barra, hueco si está apagado.
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7
                                height: 7
                                radius: width / 2
                                color: toggle.shown ? Theme.m3Primary : "transparent"
                                border.width: toggle.shown ? 0 : 1
                                border.color: Theme.textDim
                            }

                            Text {
                                id: toggleLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: toggle.modelData.label
                                color: toggle.shown ? Theme.text : Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleMeter(toggle.modelData.key)
                        }
                    }
                }
            }
        }

        // Estadísticas de la ventana muestreada.
        Row {
            id: stats
            width: parent.width
            spacing: 8

            Repeater {
                model: [
                    { label: "Actual", value: root.currentValue },
                    { label: "Máx", value: root.seriesMax },
                    { label: "Mín", value: root.seriesMin },
                    { label: "Media", value: root.seriesAvg }
                ]

                delegate: Rectangle {
                    id: stat

                    required property var modelData

                    width: Math.floor((stats.width - (stats.spacing * 3)) / 4)
                    height: 52
                    radius: 14
                    color: Theme.chip

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: stat.modelData.label
                            color: Theme.textDim
                            font.family: Theme.fontUI
                            font.pixelSize: 11
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.formatValue(stat.modelData.value)
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}

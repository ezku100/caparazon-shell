import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../../theme"

// Pager de escritorios virtuales de KWin.
// KWin no expone ext-workspace, así que vamos por DBus:
//   - estado: busctl --json=short (JSON limpio, parseable con JSON.parse)
//   - cambios en vivo: dbus-monitor escuchando la interfaz de KWin
//   - cambiar: org.kde.KWin.setCurrentDesktop(int) (1-based)
Row {
    id: root

    spacing: 4

    property var desks: []
    property string currentId: ""
    property string screenName: ""
    readonly property var occupiedIds: {
        const perScreen = stateAdapter.occupiedPerOutput;
        if (root.screenName && perScreen && perScreen[root.screenName] !== undefined)
            return perScreen[root.screenName];
        return stateAdapter.occupied;
    }
    readonly property bool occupancyKnown: stateFile.loaded

    // KWin mantiene un escritorio actual por salida cuando
    // PerOutputVirtualDesktops está activo. El puente publica ese mapa para
    // que cada barra marque su propia pantalla, no el escritorio global.
    readonly property string screenCurrentId: {
        const map = stateAdapter.perOutput;
        if (root.screenName && map && typeof map[root.screenName] === "string"
                && map[root.screenName].length > 0)
            return map[root.screenName];
        return root.currentId;
    }

    // Si el puente todavía no conoce el foco, mantenemos el comportamiento
    // anterior (halo en el activo) en vez de apagarlo en ambas pantallas.
    readonly property bool screenFocused: stateAdapter.focusedScreen === ""
        || root.screenName === ""
        || stateAdapter.focusedScreen === root.screenName

    // El puente ezkudesktops publica los escritorios con ventanas en este
    // archivo. Si todavía no existe, no oscurecemos nada por precaución.
    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.cache/ezku-desktops.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: stateAdapter
            property var occupied: []
            property var occupiedPerOutput: ({})
            property var perOutput: ({})
            property string focusedScreen: ""
        }
    }

    // Números en kanji (1-99): 1 → 一, 10 → 十, 21 → 二十一.
    function kanji(n) {
        const d = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"];
        if (n <= 0 || n > 99)
            return String(n);
        if (n < 10)
            return d[n];
        const tens = Math.floor(n / 10);
        const ones = n % 10;
        return (tens === 1 ? "" : d[tens]) + "十" + (ones ? d[ones] : "");
    }

    function refresh() {
        if (!fetch.running)
            fetch.running = true;
        if (!fetchCurrent.running)
            fetchCurrent.running = true;
    }

    Process {
        id: fetch
        command: ["busctl", "--user", "--json=short", "call", "org.kde.KWin",
                  "/VirtualDesktopManager", "org.freedesktop.DBus.Properties", "Get",
                  "ss", "org.kde.KWin.VirtualDesktopManager", "desktops"]
        stdout: StdioCollector {
            id: outDesks
            onStreamFinished: {
                try {
                    const j = JSON.parse(outDesks.text);
                    root.desks = j.data[0].data.map(function (e) {
                        return { pos: e[0], id: e[1], name: e[2] };
                    });
                } catch (e) {
                    console.log("caparazon: fallo al parsear escritorios:", e);
                }
            }
        }
    }

    Process {
        id: fetchCurrent
        command: ["busctl", "--user", "--json=short", "call", "org.kde.KWin",
                  "/VirtualDesktopManager", "org.freedesktop.DBus.Properties", "Get",
                  "ss", "org.kde.KWin.VirtualDesktopManager", "current"]
        stdout: StdioCollector {
            id: outCurrent
            onStreamFinished: {
                try {
                    root.currentId = JSON.parse(outCurrent.text).data[0].data;
                } catch (e) { }
            }
        }
    }

    Process {
        id: watcher
        running: true
        command: ["dbus-monitor", "--session",
                  "type='signal',interface='org.kde.KWin.VirtualDesktopManager'"]
        stdout: SplitParser {
            onRead: function (line) { root.refresh(); }
        }
    }

    Component.onCompleted: refresh()

    Repeater {
        model: root.desks

        delegate: Item {
            id: pill
            required property var modelData

            readonly property bool active: modelData.id === root.screenCurrentId
            readonly property bool hasApps: root.occupancyKnown
                && root.occupiedIds.indexOf(modelData.id) !== -1
            readonly property color activeColor: root.screenFocused
                ? Theme.m3Primary
                : Theme.text

            width: 26
            height: 26

            // Mismo círculo de fondo que el resto de iconos de la barra.
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.lighter(Theme.chipHover, 1.3)
            }

            // Halo activo: degradado radial dentro del círculo, sin desbordar.
            Shape {
                anchors.fill: parent
                visible: pill.active && root.screenFocused
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: 13
                        centerY: 13
                        centerRadius: 0
                        focalX: 13
                        focalY: 13
                        focalRadius: 13

                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(Theme.glowColor.r, Theme.glowColor.g, Theme.glowColor.b, 0.55)
                        }
                        GradientStop {
                            position: 0.55
                            color: Qt.rgba(Theme.glowColor.r, Theme.glowColor.g, Theme.glowColor.b, 0.18)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(Theme.glowColor.r, Theme.glowColor.g, Theme.glowColor.b, 0.0)
                        }
                    }

                    startX: 13
                    startY: 0

                    PathAngleArc {
                        centerX: 13
                        centerY: 13
                        radiusX: 13
                        radiusY: 13
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }

            // Número nítido.
            Text {
                id: num
                anchors.centerIn: parent
                text: root.kanji(pill.modelData.pos + 1)
                color: pill.active
                    ? pill.activeColor
                    : (root.occupancyKnown && !pill.hasApps
                        ? Qt.darker(Theme.textDim, 1.6)
                        : Theme.textDim)
                font.family: Theme.fontJP
                font.pixelSize: 15
                font.weight: Font.Bold
                font.hintingPreference: Font.PreferFullHinting
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached([
                    "qdbus6", "org.kde.KWin", "/KWin",
                    "org.kde.KWin.setCurrentDesktop",
                    String(pill.modelData.pos + 1)
                ])
            }
        }
    }
}

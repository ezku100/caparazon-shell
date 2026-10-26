import Quickshell
import Quickshell.Io
import QtQuick

// Servicio global de escritorios virtuales: una sola instancia para todas las barras.
// Evita duplicar el watcher dbus-monitor y la lectura de ezku-desktops.json por monitor.
Item {
    id: root
    visible: false

    property var queriedDesks: []
    property string queriedCurrentId: ""
    // La consulta directa a KWin es la fuente principal. El puente local ya
    // publica la misma lista en caché y sirve de respaldo si KWin no responde.
    readonly property var desks: queriedDesks.length > 0
        ? queriedDesks
        : stateAdapter.desktops
    readonly property string currentId: queriedCurrentId.length > 0
        ? queriedCurrentId
        : stateAdapter.current

    readonly property bool occupancyKnown: stateFile.loaded

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
            property var desktops: []
            property string current: ""
        }
    }

    function occupiedIds(screenName) {
        const perScreen = stateAdapter.occupiedPerOutput;
        if (screenName && perScreen && perScreen[screenName] !== undefined)
            return perScreen[screenName];
        return stateAdapter.occupied;
    }

    function screenCurrentId(screenName) {
        const map = stateAdapter.perOutput;
        if (screenName && map && typeof map[screenName] === "string" && map[screenName].length > 0)
            return map[screenName];
        return root.currentId;
    }

    function screenFocused(screenName) {
        return stateAdapter.focusedScreen === ""
            || screenName === ""
            || stateAdapter.focusedScreen === screenName;
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
                    root.queriedDesks = j.data[0].data.map(function (e) {
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
                    root.queriedCurrentId = JSON.parse(outCurrent.text).data[0].data;
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

    Component.onCompleted: {
        console.log("WorkspacesService init");
        refresh();
    }
}

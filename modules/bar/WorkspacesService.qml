import Quickshell
import Quickshell.Io
import QtQuick

// Servicio global de escritorios: una sola instancia para todas las barras.
// Habla con caparazon-wm (kwin o niri); la ocupación y el estado vienen en
// el mismo JSON. El caché local sigue de respaldo si el CLI falla.
Item {
    id: root
    visible: false

    property var queriedDesks: []
    property string queriedCurrentId: ""
    property var queriedOccupied: []
    property var queriedOccupiedPerOutput: ({})
    property var queriedPerOutput: ({})
    property string queriedFocusedScreen: ""

    readonly property var desks: queriedDesks.length > 0
        ? queriedDesks
        : stateAdapter.desktops
    readonly property string currentId: queriedCurrentId.length > 0
        ? queriedCurrentId
        : stateAdapter.current

    readonly property bool occupancyKnown:
        queriedOccupied.length > 0 || stateFile.loaded

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
        if (queriedOccupiedPerOutput && screenName
                && queriedOccupiedPerOutput[screenName] !== undefined)
            return queriedOccupiedPerOutput[screenName];
        if (queriedOccupied.length > 0)
            return queriedOccupied;
        const perScreen = stateAdapter.occupiedPerOutput;
        if (screenName && perScreen && perScreen[screenName] !== undefined)
            return perScreen[screenName];
        return stateAdapter.occupied;
    }

    function screenCurrentId(screenName) {
        const map = queriedPerOutput && Object.keys(queriedPerOutput).length > 0
            ? queriedPerOutput
            : stateAdapter.perOutput;
        if (screenName && map && typeof map[screenName] === "string"
                && map[screenName].length > 0)
            return map[screenName];
        return root.currentId;
    }

    function screenFocused(screenName) {
        const focused = queriedFocusedScreen || stateAdapter.focusedScreen;
        return focused === ""
            || screenName === ""
            || focused === screenName;
    }

    function refresh() {
        if (!fetch.running)
            fetch.running = true;
    }

    function applyState(doc) {
        if (!doc || typeof doc !== "object")
            return;
        if (Array.isArray(doc.desktops))
            root.queriedDesks = doc.desktops;
        if (typeof doc.current === "string")
            root.queriedCurrentId = doc.current;
        if (Array.isArray(doc.occupied))
            root.queriedOccupied = doc.occupied;
        if (doc.perOutput && typeof doc.perOutput === "object")
            root.queriedPerOutput = doc.perOutput;
        if (doc.occupiedPerOutput && typeof doc.occupiedPerOutput === "object")
            root.queriedOccupiedPerOutput = doc.occupiedPerOutput;
        if (typeof doc.focusedScreen === "string")
            root.queriedFocusedScreen = doc.focusedScreen;
    }

    Process {
        id: fetch
        command: ["caparazon-wm", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyState(JSON.parse(text));
                } catch (e) {
                    console.log("caparazon: fallo al parsear escritorios:", e);
                }
            }
        }
    }

    Process {
        id: watcher
        running: true
        command: ["caparazon-wm", "watch-workspaces"]
        stdout: SplitParser {
            onRead: function(line) {
                if (!line || line.length === 0)
                    return;
                try {
                    root.applyState(JSON.parse(line));
                } catch (e) { }
            }
        }
    }

    Component.onCompleted: {
        console.log("WorkspacesService init");
        refresh();
    }
}

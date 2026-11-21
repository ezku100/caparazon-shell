import Quickshell
import Quickshell.Io
import QtQuick

// Watcher único para toda la shell: caparazon-wm expone el estado de
// ventanas (KWin vía script/journal o niri vía IPC) con el mismo shape.
Item {
    id: root
    visible: false

    property string appId: ""
    property string title: ""
    property var windowAppIds: []

    function applyState(doc) {
        if (!doc || typeof doc !== "object")
            return;
        if (typeof doc.appId === "string")
            root.appId = doc.appId;
        if (typeof doc.title === "string")
            root.title = doc.title;
        if (Array.isArray(doc.appIds))
            root.windowAppIds = doc.appIds;
    }

    Process {
        id: fetch
        command: ["caparazon-wm", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyState(JSON.parse(text));
                } catch (e) {
                    console.log("caparazon: fallo al parsear ventanas:", e);
                }
            }
        }
    }

    Process {
        id: watcher
        running: true
        command: ["caparazon-wm", "watch-windows"]
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

    // Respaldo: si tras arrancar aún no llegó lista de ventanas, reintenta.
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            if (root.windowAppIds.length === 0 && !fetch.running)
                fetch.running = true;
        }
    }

    Component.onCompleted: {
        console.log("ActiveWindowService init");
        if (!fetch.running)
            fetch.running = true;
    }
}

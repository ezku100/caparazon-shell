import Quickshell
import Quickshell.Io
import QtQuick

// Historial de portapapeles de la shell. Quickshell sólo expone el contenido
// actual (Quickshell.clipboardText), así que un watcher de wl-paste guarda
// cada cambio en ~/.cache/caparazon/clipboard-history.json.
Item {
    id: root

    visible: false

    readonly property string cacheHome: {
        const xdg = Quickshell.env("XDG_CACHE_HOME");
        return (xdg && xdg.length > 0) ? xdg : Quickshell.env("HOME") + "/.cache";
    }
    readonly property string historyDir: root.cacheHome + "/caparazon"
    readonly property string historyPath: root.historyDir + "/clipboard-history.json"
    readonly property var items: {
        const list = adapter.items;
        return list && typeof list.length === "number" ? list : [];
    }

    // Crea el archivo vacío antes de que FileView intente leerlo.
    Process {
        id: ensureFile
        running: true
        command: [
            "bash", "-c",
            "mkdir -p \"$1\"; [ -f \"$2\" ] || printf '%s\\n' '{\"items\":[]}' > \"$2\"",
            "bash",
            root.historyDir,
            root.historyPath
        ]
        onExited: file.reload()
    }

    FileView {
        id: file
        path: root.historyPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property var items: []
        }
    }

    Process {
        id: watcher
        running: true
        command: [
            "wl-paste",
            "--watch",
            "python3",
            Quickshell.shellPath("modules/appmenu/clipboard-watch.py")
        ]
        onExited: restartTimer.restart()
    }

    Timer {
        id: restartTimer
        interval: 1200
        onTriggered: {
            if (!watcher.running)
                watcher.running = true;
        }
    }

    function clear() {
        adapter.items = [];
        file.writeAdapter();
    }
}

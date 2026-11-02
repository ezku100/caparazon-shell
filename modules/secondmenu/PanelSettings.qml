import Quickshell
import Quickshell.Io
import QtQuick

/*
  Recuerda si la columna izquierda del menú secundario muestra las
  notificaciones o los eventos del día.

  El fichero es un JSON mínimo: {"view": "events"}. Vive en la caché de
  Caparazón y se escribe de forma atómica (a un .tmp y renombrando), como el
  resto de estado del repo.
*/
Item {
    id: root
    visible: false

    readonly property string settingsDir: Quickshell.env("HOME") + "/.cache/caparazon"
    readonly property string settingsPath: settingsDir + "/secondmenu.json"

    property string view: "notifications"
    property bool loaded: false

    onViewChanged: save()

    function setView(value) {
        if (value !== "events" && value !== "notifications")
            return;
        if (root.view === value)
            return;

        root.view = value;
    }

    function save() {
        if (!root.loaded)
            return;

        const value = root.view === "events" ? "events" : "notifications";
        writer.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"",
            "bash",
            "{\"view\":\"" + value + "\"}",
            root.settingsPath
        ];
        writer.running = true;
    }

    Process {
        id: ensureFile
        running: true
        command: [
            "bash", "-c",
            "mkdir -p \"$1\"; [ -f \"$2\" ] || printf '%s\\n' '{\"view\":\"notifications\"}' > \"$2\"",
            "bash",
            root.settingsDir,
            root.settingsPath
        ]
        onExited: file.reload()
    }

    Process {
        id: writer
    }

    FileView {
        id: file
        path: root.settingsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property string view: "notifications"
        }
    }

    Connections {
        target: file
        function onLoaded() {
            if (root.loaded)
                return;

            root.view = adapter.view === "events" ? "events" : "notifications";
            root.loaded = true;
        }
    }
}

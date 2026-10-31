import Quickshell
import Quickshell.Io
import QtQuick

/*
  Recuerda el modo compacto de la categoría Música.

  El fichero es un JSON mínimo: {"compact": true}. Vive en la caché de
  Caparazón y se escribe de forma atómica (a un .tmp y renombrando), como el
  resto de estado del repo.
*/
Item {
    id: root
    visible: false

    readonly property string settingsDir: Quickshell.env("HOME") + "/.cache/caparazon"
    readonly property string settingsPath: settingsDir + "/music-panel.json"

    // Modo compacto actual. Cambiarlo guarda la elección.
    property bool compact: false

    // true cuando ya se leyó el fichero: antes de eso no se guarda nada,
    // para no pisar la preferencia con el valor por defecto.
    property bool loaded: false

    onCompactChanged: save()

    function save() {
        if (!loaded)
            return;

        persist.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2\".tmp && mv \"$2\".tmp \"$2\"",
            "bash",
            JSON.stringify({ compact: root.compact }),
            root.settingsPath
        ];
        persist.running = true;
    }

    // Crea el fichero si no existe, para que el FileView no falle al leer.
    Process {
        id: ensureFile
        running: true
        command: [
            "bash", "-c",
            "mkdir -p \"$1\"; [ -f \"$2\" ] || printf '%s\\n' '{\"compact\":false}' > \"$2\"",
            "bash",
            root.settingsDir,
            root.settingsPath
        ]
        onExited: file.reload()
    }

    Process {
        id: persist
    }

    FileView {
        id: file
        path: root.settingsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool compact: false
        }
    }

    // Al terminar la primera carga se aplica lo que había guardado. El orden
    // importa: primero el valor, luego `loaded`, para que el cambio no se
    // guarde de vuelta.
    Connections {
        target: file
        function onLoadedChanged() {
            if (!file.loaded || root.loaded)
                return;

            root.compact = adapter.compact;
            root.loaded = true;
        }
    }
}

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

    // Cambia el modo compacto desde el panel. Si el valor no cambia no hace
    // nada, así la carga inicial no reescribe el fichero.
    function setCompact(value) {
        if (root.compact === value)
            return;

        root.compact = value;
    }

    function save() {
        if (!loaded)
            return;

        adapter.compact = root.compact;
        file.writeAdapter();
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

    // `loaded` es una señal que se emite cuando el fichero ya está leído y el
    // adapter relleno. La propiedad homónima se pone a true al *empezar* la
    // carga asíncrona, así que leer el adapter con ella devolvía el valor por
    // defecto.
    Connections {
        target: file
        function onLoaded() {
            if (root.loaded)
                return;

            root.compact = adapter.compact;
            root.loaded = true;
        }
    }
}

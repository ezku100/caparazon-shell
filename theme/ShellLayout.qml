pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Dónde vive la shell: las dos opciones del panel ("barra en monitores
// secundarios" y "dock en monitores secundarios") se guardan en
// ~/.config/caparazon/display.json.
//
// El monitor principal es el que KDE considera principal, no el primero de
// la lista: se pregunta a kscreen (la misma prioridad que reporta
// kscreen-doctor), igual que hace el propio Plasma.
Item {
    id: root
    visible: false

    property bool barOnSecondary: true
    property bool dockOnSecondary: true
    property bool loaded: false
    property bool syncing: false

    // Conector principal según KDE; vacío hasta la primera consulta.
    property string primaryName: ""

    readonly property string configDir: Quickshell.env("HOME") + "/.config/caparazon"
    readonly property string configPath: root.configDir + "/display.json"

    readonly property var screens: Quickshell.screens

    readonly property var primaryScreen: {
        const list = root.screens;
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].name === root.primaryName)
                return list[i];
        }
        // Sin respuesta de kscreen todavía: la primera pantalla.
        return list.length > 0 ? list[0] : null;
    }

    // Pantallas donde se instala la barra y el dock.
    readonly property var barScreens: root.screensFor(root.barOnSecondary)
    readonly property var dockScreens: root.screensFor(root.dockOnSecondary)

    function screensFor(showOnSecondary) {
        if (showOnSecondary || !root.primaryScreen)
            return root.screens;
        return [root.primaryScreen];
    }

    function setBarOnSecondary(value) {
        if (root.barOnSecondary === value)
            return;
        root.barOnSecondary = value;
    }

    function setDockOnSecondary(value) {
        if (root.dockOnSecondary === value)
            return;
        root.dockOnSecondary = value;
    }

    // Al leer el archivo no se reescribe; al cambiarlo desde el panel sí.
    onBarOnSecondaryChanged: if (!root.syncing) root.save()
    onDockOnSecondaryChanged: if (!root.syncing) root.save()

    function save() {
        if (!root.loaded)
            return;
        writer.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"",
            "bash",
            "{\"barSecondary\":" + (root.barOnSecondary ? "true" : "false")
                + ",\"dockSecondary\":" + (root.dockOnSecondary ? "true" : "false") + "}",
            root.configPath
        ];
        writer.running = true;
    }

    Component.onCompleted: probe.running = true

    // Otra pantalla conectada o desconectada: se vuelve a preguntar.
    onScreensChanged: if (!probe.running) probe.running = true

    Process {
        id: probe
        command: ["kscreen-doctor", "--json", "-o"]
        stdout: StdioCollector {
            onStreamFinished: root.parsePrimary(text)
        }
    }

    // kscreen-doctor imprime el JSON y después su resumen en texto; se
    // recorta el objeto antes de parsearlo. La principal es la de menor
    // prioridad (1) entre las pantallas activas.
    function parsePrimary(raw) {
        if (!raw)
            return;
        const start = raw.indexOf("{");
        const end = raw.lastIndexOf("}");
        if (start < 0 || end <= start)
            return;
        let doc = null;
        try {
            doc = JSON.parse(raw.substring(start, end + 1));
        } catch (e) {
            return;
        }
        const outs = doc && doc.outputs ? doc.outputs : [];
        let best = null;
        for (let i = 0; i < outs.length; i++) {
            const out = outs[i];
            if (!out || !out.name)
                continue;
            if (out.enabled === false || out.connected === false)
                continue;
            const priority = typeof out.priority === "number" ? out.priority : 0;
            if (priority <= 0)
                continue;
            if (!best || priority < best.priority)
                best = { name: out.name, priority: priority };
        }
        if (best)
            root.primaryName = best.name;
    }

    Process {
        id: ensureFile
        running: true
        command: [
            "bash", "-c",
            "mkdir -p \"$1\"; [ -f \"$2\" ] || "
                + "printf '%s\\n' '{\"barSecondary\":true,\"dockSecondary\":true}' > \"$2\"",
            "bash",
            root.configDir,
            root.configPath
        ]
        onExited: file.reload()
    }

    Process {
        id: writer
    }

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool barSecondary: true
            property bool dockSecondary: true
        }
    }

    Connections {
        target: file
        function onLoaded() {
            // También se aplica si el archivo cambia desde fuera.
            root.syncing = true;
            root.barOnSecondary = adapter.barSecondary !== false;
            root.dockOnSecondary = adapter.dockSecondary !== false;
            root.syncing = false;
            root.loaded = true;
        }
    }
}

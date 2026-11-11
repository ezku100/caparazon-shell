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

    property bool barOnPrimary: true
    property bool barOnSecondary: true
    property bool dockOnPrimary: true
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

    readonly property bool hasSecondaryScreen: root.screens.length > 1

    // Apagar la barra en el principal sólo se permite si otra pantalla se
    // queda con ella: es la única vía de acceso a los menús. El dock no
    // necesita la salvaguarda (el panel sigue disponible en la barra).
    readonly property bool barPrimaryCanTurnOff:
        root.hasSecondaryScreen && root.barOnSecondary

    function screensFor(onPrimary, onSecondary) {
        const list = root.screens;
        const primary = root.primaryScreen;
        const result = [];
        for (let i = 0; i < list.length; i++) {
            const screen = list[i];
            if (!screen)
                continue;
            const isPrimary = primary !== null && screen.name === primary.name;
            if (isPrimary ? onPrimary : onSecondary)
                result.push(screen);
        }
        return result;
    }

    // La barra no se destruye en las pantallas donde está apagada: se oculta
    // (la ventana y sus menús tienen que seguir vivos para el dock y los
    // atajos). Devuelve si debe verse en esa pantalla.
    function barShownFor(screen) {
        if (!screen)
            return false;
        const primary = root.primaryScreen;
        const isPrimary = primary !== null && screen.name === primary.name;
        if (!isPrimary)
            return root.barOnSecondary;
        if (root.barOnPrimary)
            return true;
        // Config a mano sin ninguna barra: se deja en el principal para no
        // perder el acceso al panel.
        return !root.hasSecondaryScreen || !root.barOnSecondary;
    }

    readonly property var dockScreens:
        root.screensFor(root.dockOnPrimary, root.dockOnSecondary)

    function setBarOnPrimary(value) {
        if (root.barOnPrimary === value)
            return;
        if (!value && !root.barPrimaryCanTurnOff)
            return;
        root.barOnPrimary = value;
    }

    function setBarOnSecondary(value) {
        if (root.barOnSecondary === value)
            return;
        root.barOnSecondary = value;
    }

    function setDockOnPrimary(value) {
        if (root.dockOnPrimary === value)
            return;
        root.dockOnPrimary = value;
    }

    function setDockOnSecondary(value) {
        if (root.dockOnSecondary === value)
            return;
        root.dockOnSecondary = value;
    }

    // Al leer el archivo no se reescribe; al cambiarlo desde el panel sí.
    onBarOnPrimaryChanged: if (!root.syncing) root.save()
    onBarOnSecondaryChanged: if (!root.syncing) root.save()
    onDockOnPrimaryChanged: if (!root.syncing) root.save()
    onDockOnSecondaryChanged: if (!root.syncing) root.save()

    function save() {
        if (!root.loaded)
            return;
        writer.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"",
            "bash",
            "{\"barPrimary\":" + (root.barOnPrimary ? "true" : "false")
                + ",\"barSecondary\":" + (root.barOnSecondary ? "true" : "false")
                + ",\"dockPrimary\":" + (root.dockOnPrimary ? "true" : "false")
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
                + "printf '%s\\n' '{\"barPrimary\":true,\"barSecondary\":true,"
                + "\"dockPrimary\":true,\"dockSecondary\":true}' > \"$2\"",
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
            property bool barPrimary: true
            property bool barSecondary: true
            property bool dockPrimary: true
            property bool dockSecondary: true
        }
    }

    Connections {
        target: file
        function onLoaded() {
            // También se aplica si el archivo cambia desde fuera.
            root.syncing = true;
            root.barOnPrimary = adapter.barPrimary !== false;
            root.barOnSecondary = adapter.barSecondary !== false;
            root.dockOnPrimary = adapter.dockPrimary !== false;
            root.dockOnSecondary = adapter.dockSecondary !== false;
            root.syncing = false;
            root.loaded = true;
        }
    }
}

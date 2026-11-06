pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
  Estilo de color activo de la shell: material, oled o perla.

  Se guarda en ~/.config/caparazon/style.json como {"style":"oled"} y se
  escribe de forma atómica (a un .tmp y renombrando). MatugenPalette lee la
  paleta que corresponde al estilo elegido.
*/
Item {
    id: root
    visible: false

    readonly property var styles: ["material", "oled", "perla"]
    readonly property string configDir: Quickshell.env("HOME") + "/.config/caparazon"
    readonly property string configPath: configDir + "/style.json"

    readonly property string paletteCacheDir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME")
        const base = (xdg && xdg.length > 0) ? xdg : Quickshell.env("HOME") + "/.cache"
        return base + "/caparazon"
    }

    property string style: "material"
    property bool loaded: false

    readonly property string paletteFile: {
        if (root.style === "oled")
            return "colors-oled.json";
        if (root.style === "perla")
            return "colors-perla.json";
        return "colors.json";
    }

    function palettePathFor(name) {
        if (name === "oled")
            return root.paletteCacheDir + "/colors-oled.json";
        if (name === "perla")
            return root.paletteCacheDir + "/colors-perla.json";
        return root.paletteCacheDir + "/colors.json";
    }

    function setStyle(value) {
        if (root.styles.indexOf(value) === -1)
            return;
        if (root.style === value)
            return;

        root.style = value;
    }

    function save() {
        if (!root.loaded)
            return;

        writer.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"",
            "bash",
            "{\"style\":\"" + root.style + "\"}",
            root.configPath
        ];
        writer.running = true;
    }

    onStyleChanged: save()

    Process {
        id: ensureFile
        running: true
        command: [
            "bash", "-c",
            "mkdir -p \"$1\"; [ -f \"$2\" ] || printf '%s\\n' '{\"style\":\"material\"}' > \"$2\"",
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
            property string style: "material"
        }
    }

    Connections {
        target: file
        function onLoaded() {
            if (root.loaded)
                return;

            root.style = root.styles.indexOf(adapter.style) === -1
                ? "material"
                : adapter.style;
            root.loaded = true;
        }
    }
}

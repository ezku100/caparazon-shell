pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
  Estilo de color activo de la shell: material, oled o perla.

  Se guarda en ~/.config/caparazon/style.json como
  {"style":"oled","auto":false} y se escribe de forma atómica (a un .tmp y
  renombrando). MatugenPalette lee la paleta que corresponde al estilo.

  Con "auto" activo el estilo lo elige la hora: mañana Perla, tarde Material
  y noche OLED. El reloj revisa cada medio minuto y reaplica al cruzar una
  franja; al apagarlo se queda el estilo que estuviera puesto.
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
    property bool autoStyle: false
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

    function styleForHour(hour) {
        if (hour >= 6 && hour < 12)
            return "perla";
        if (hour >= 12 && hour < 19)
            return "material";
        return "oled";
    }

    function applyAutoStyle() {
        if (!root.autoStyle)
            return;
        root.setStyle(root.styleForHour(new Date().getHours()));
    }

    function setAutoStyle(value) {
        if (root.autoStyle === value)
            return;
        root.autoStyle = value;
        root.applyAutoStyle();
    }

    function save() {
        if (!root.loaded)
            return;

        writer.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"",
            "bash",
            "{\"style\":\"" + root.style + "\",\"auto\":"
                + (root.autoStyle ? "true" : "false") + "}",
            root.configPath
        ];
        writer.running = true;
    }

    onStyleChanged: save()
    onAutoStyleChanged: save()

    Timer {
        interval: 30000
        repeat: true
        running: root.autoStyle
        onTriggered: root.applyAutoStyle()
    }

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
            property bool auto: false
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
            root.autoStyle = adapter.auto === true;
            root.loaded = true;
            if (root.autoStyle)
                root.applyAutoStyle();
        }
    }
}

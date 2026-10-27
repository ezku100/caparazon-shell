import Quickshell
import Quickshell.Io
import QtQuick
import "IconTheme.js" as IconTheme

// Vigilante del tema de iconos de KDE.
//
// El tema de iconos se lee una sola vez por proceso: Qt lo carga al
// arrancar y no vuelve a mirarlo. Así que, cuando KDE cambia de tema, la
// única forma de que los iconos cambien es reiniciar la shell.
//
// Este servicio vigila kdeglobals, compara el valor de [Icons] Theme con el
// que ya conoce y, si ha cambiado de verdad, reinicia la shell:
//   - bajo systemd, la unidad de la shell, mediante una unidad transitoria
//     que vive fuera de su cgroup, para que el reinicio no se mate a sí
//     mismo a media faena;
//   - sin systemd, el mismo argv que la arrancó, en cuanto el proceso
//     actual muere.
//
// La decisión la toma IconTheme.js, que se puede probar sin la shell.
Item {
    id: root
    visible: false

    readonly property string configDir: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        return (xdg && xdg.length > 0) ? xdg : Quickshell.env("HOME") + "/.config";
    }

    readonly property string configFile: configDir + "/kdeglobals"

    // Último tema conocido.
    property string currentTheme: ""
    // Si ya se ha visto un tema real: el primero sólo fija la línea base,
    // porque el proceso ya ha arrancado con él.
    property bool baselineKnown: false
    // Evita encolar dos reinicios por el mismo cambio.
    property bool restarting: false

    // PID de la shell y su argv, para el relanzamiento sin systemd.
    property int selfPid: 0
    property var selfArgv: []

    // Lee el archivo y compara el tema con el que ya conoce.
    function checkTheme() {
        applyTheme(IconTheme.iconTheme(globals.text()));
    }

    function scheduleCheck() {
        debounce.restart();
    }

    function applyTheme(value) {
        const decision = IconTheme.themeDecision(currentTheme, value, baselineKnown);
        currentTheme = decision.theme;
        baselineKnown = true;
        if (decision.restart)
            requestRestart();
    }

    function requestRestart() {
        if (restarting)
            return;
        restarting = true;
        restartGuard.restart();
        processState.running = true;
    }

    // Reinicia la shell según dónde esté corriendo.
    function restart() {
        const unit = unitName;
        if (unit.length > 0) {
            Quickshell.execDetached(IconTheme.restartCommand(unit));
            return;
        }
        if (selfPid > 0 && selfArgv.length > 0) {
            Quickshell.execDetached(IconTheme.relaunchCommand(selfPid, selfArgv));
            return;
        }
        console.warn("Caparazon: el tema de iconos cambio pero no se sabe como "
            + "reiniciar la shell");
    }

    // Nombre de la unidad de la shell, deducido del cgroup.
    //
    // Sólo vale el último tramo: los anteriores incluyen el gestor de
    // usuario, y reiniciar ése cerraría la sesión entera. El gestor de
    // usuario y el de sistema se descartan también por si acaso.
    readonly property string unitName: {
        const parts = String(root.cgroupPath).split("/");
        const last = parts.length > 0 ? parts[parts.length - 1] : "";
        if (!last.endsWith(".service"))
            return "";
        if (last.startsWith("user@") || last.startsWith("user-"))
            return "";
        if (last === "init.service")
            return "";
        return last;
    }

    // Ruta del cgroup de este proceso.
    property string cgroupPath: ""

    // Interpreta la salida del proceso de estado.
    function applyProcessState(output) {
        const lines = String(output || "").split("\n");
        let pid = 0;
        let unitPath = "";
        const argv = [];
        let readingArgv = false;

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (line === "ARGV") {
                readingArgv = true;
                continue;
            }
            if (line.startsWith("PID=")) {
                pid = parseInt(line.slice(4), 10) || 0;
                continue;
            }
            if (line.startsWith("UNIT=")) {
                unitPath = line.slice(5).trim();
                continue;
            }
            if (readingArgv && line.length > 0)
                argv.push(line);
        }

        selfPid = pid;
        selfArgv = argv;
        cgroupPath = unitPath;
        restart();
    }

    // El archivo de configuración de KDE.
    FileView {
        id: globals
        path: root.configFile
        watchChanges: true
        printErrors: false

        onLoaded: root.checkTheme()
        onFileChanged: {
            reload();
            root.scheduleCheck();
        }
    }

    // Red de seguridad: si la vigilancia del archivo se pierde, el sondeo
    // sigue mirando. KConfig sustituye kdeglobals de forma atómica y el
    // watchChanges aguanta, pero un fallo silencioso aquí dejaría al
    // usuario con el tema viejo sin saber por qué.
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.scheduleCheck()
    }

    // KConfig reescribe el archivo entero; se espera a que se asiente.
    Timer {
        id: debounce
        interval: 500
        onTriggered: root.checkTheme()
    }

    // Si el reinicio falla, se vuelve a intentar en el siguiente cambio.
    Timer {
        id: restartGuard
        interval: 3000
        onTriggered: root.restarting = false
    }

    // Estado del proceso: dónde corre y con qué argumentos arrancó.
    Process {
        id: processState
        command: [
            "sh", "-c",
            "printf 'PID=%s\\n' \"$PPID\"; "
                + "printf 'UNIT='; tr '\\0' '\\n' < /proc/self/cgroup | tail -n 1; "
                + "printf 'ARGV\\n'; tr '\\0' '\\n' < /proc/$PPID/cmdline"
        ]

        stdout: StdioCollector {
            onStreamFinished: root.applyProcessState(text)
        }
    }
}

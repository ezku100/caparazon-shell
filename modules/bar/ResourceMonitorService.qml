import Quickshell
import Quickshell.Io
import QtQuick

// Una sola instancia para toda la shell: evita un proceso de muestreo por
// monitor. El script entrega los valores una vez por segundo.
Item {
    id: root
    visible: false

    property int cpu: 0
    property int ram: 0
    property int gpu: 0
    property int swap: 0
    property int network: 0
    property int temperature: 0
    property string powerProfile: "balanced"

    // Historial para los gráficos del panel: una muestra por segundo con los
    // últimos dos minutos.
    readonly property int historySize: 120
    property var samples: []

    // Medidores apagados desde la barra (por clave: cpu, ram, gpu, ...). Se
    // guardan en disco para que sigan apagados tras reiniciar la shell.
    readonly property string metersPath: Quickshell.env("HOME")
        + "/.config/caparazon-shell/meters.json"
    property var hiddenMeters: []

    function clamp(value) {
        return Math.max(0, Math.min(100, Math.round(Number(value) || 0)));
    }

    function pushSample(sample) {
        const next = root.samples.concat([sample]);
        root.samples = next.length > root.historySize
            ? next.slice(next.length - root.historySize)
            : next;
    }

    function isHidden(key) {
        return root.hiddenMeters.indexOf(key) >= 0;
    }

    function toggleMeter(key) {
        const next = root.hiddenMeters.slice();
        const index = next.indexOf(key);
        if (index >= 0)
            next.splice(index, 1);
        else
            next.push(key);
        root.saveMeters(next);
    }

    function restoreMeters() {
        root.saveMeters([]);
    }

    function saveMeters(meters) {
        metersAdapter.hidden = meters;
        metersFile.writeAdapter();
    }

    // El adaptador carga de forma asíncrona: al terminar se copia lo guardado
    // en memoria, que es lo que consultan los anillos de la barra.
    function adoptStoredMeters() {
        const stored = metersAdapter.hidden;
        const meters = [];
        if (stored) {
            for (let index = 0; index < stored.length; index++)
                meters.push(String(stored[index]));
        }
        root.hiddenMeters = meters;
    }

    FileView {
        id: metersFile
        path: root.metersPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.adoptStoredMeters()

        JsonAdapter {
            id: metersAdapter
            property var hidden: []
        }
    }

    // Crea la carpeta y el archivo con la forma esperada antes de leerlo.
    Process {
        id: metersInit
        running: true
        command: [
            "bash", "-c",
            "mkdir -p \"$1\"; [ -f \"$2\" ] || printf '%s\\n' '{\"hidden\":[]}' > \"$2\"",
            "bash",
            Quickshell.env("HOME") + "/.config/caparazon-shell",
            root.metersPath
        ]
        onExited: metersFile.reload()
    }

    Process {
        id: sampler
        running: true
        command: ["bash", Quickshell.shellPath("modules/bar/resource-monitor.sh")]
        stdout: SplitParser {
            onRead: function(line) {
                const fields = line.trim().split(/\s+/);
                if (fields.length < 6)
                    return;

                root.cpu = clamp(fields[0]);
                root.ram = clamp(fields[1]);
                root.gpu = clamp(fields[2]);
                root.swap = clamp(fields[3]);
                root.network = clamp(fields[4]);
                root.powerProfile = fields[5] || "balanced";
                root.temperature = Math.max(0, Math.round(Number(fields[6]) || 0));
                root.pushSample([
                    root.cpu, root.ram, root.gpu,
                    root.swap, root.network, root.temperature]);
            }
        }
    }
}

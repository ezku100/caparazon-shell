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
    property string powerProfile: "balanced"

    function clamp(value) {
        return Math.max(0, Math.min(100, Math.round(Number(value) || 0)));
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
            }
        }
    }
}

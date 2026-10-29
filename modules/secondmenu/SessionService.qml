import Quickshell
import Quickshell.Io
import QtQuick

// Tiempo de sesión activa. session.sh devuelve "<kind> <epoch>": se usa el
// último ActiveEnterTimestamp de loginctl y, si no hay, el arranque del equipo.
Item {
    id: root

    property string label: ""
    property bool systemWide: false

    readonly property string scriptPath: String(Qt.resolvedUrl("session.sh"))
        .replace(/^file:\/\//, "")

    function refresh() {
        proc.running = true;
    }

    function formatDuration(ms) {
        const mins = Math.max(0, Math.floor(ms / 60000));
        const days = Math.floor(mins / 1440);
        const hours = Math.floor((mins % 1440) / 60);
        const minutes = mins % 60;
        if (days > 0)
            return days + " d " + hours + " h";
        if (hours > 0)
            return hours + " h " + minutes + " min";
        return minutes + " min";
    }

    Process {
        id: proc
        command: ["bash", root.scriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text || "").trim().split(/\s+/);
                const epoch = Number(parts[1]);
                if (!parts[0] || isNaN(epoch)) {
                    root.label = "";
                    return;
                }
                root.systemWide = parts[0] === "system";
                root.label = root.formatDuration(Date.now() - epoch * 1000);
            }
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}

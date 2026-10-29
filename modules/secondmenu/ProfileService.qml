import Quickshell
import Quickshell.Io
import QtQuick

// Perfil del usuario: nombre visible y avatar. La búsqueda de archivos la
// hace profile.sh (primera coincidencia de las rutas habituales de caras).
Item {
    id: root

    property string userName: Quickshell.env("USER") || ""
    property string avatarSource: ""

    readonly property string scriptPath: String(Qt.resolvedUrl("profile.sh"))
        .replace(/^file:\/\//, "")

    Process {
        id: probe
        command: ["bash", root.scriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text || "").split("\n");
                const name = (lines[0] || "").trim();
                if (name.length > 0)
                    root.userName = name;
                root.avatarSource = (lines[1] || "").trim();
            }
        }
    }

    Component.onCompleted: probe.running = true
}

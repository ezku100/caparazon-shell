pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Compositor de la sesión, consultado una vez por proceso.
//
// El QML no habla con D-Bus ni con el socket de niri: pregunta al CLI, que es
// la única puerta al compositor. La respuesta se guarda aquí para que el rail
// y el panel compartan una sola consulta.
Singleton {
    id: root

    // El resultado del CLI; de fuera sólo se lee, por eso va aparte.
    property string detected: "unknown"

    readonly property string compositor: root.detected
    readonly property bool niri: root.compositor === "niri"

    Component.onCompleted: detect.running = true

    Process {
        id: detect

        command: ["caparazon-wm", "detect"]

        stdout: StdioCollector {
            onStreamFinished: root.detected = String(text || "").trim()
        }
    }
}

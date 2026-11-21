import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../icons"
import "../icons/BarIcons.js" as BarIcons
import "../../theme"

// Selector compacto del perfil de energía. La rueda del mouse cambia entre
// ahorro, equilibrado y rendimiento sin abrir ningún menú.
Item {
    id: root

    property string profile: ""
    property string displayProfile: ""
    property var choices: []
    property string backend: ""

    // El motor decide qué perfiles existen: power-profiles-daemon no ofrece
    // "performance" en todo el hardware, así que la lista viene del CLI.
    readonly property bool supported: root.choices.length > 0

    // 0 = fondo actual, 1 = estilo de énfasis. Balanced queda en medio.
    readonly property real tone: root.displayProfile === "performance" ? 1.0
        : root.displayProfile === "balanced" ? 0.5
        : 0.0
    readonly property color lowColor: Qt.lighter(Theme.chipHover, 1.3)
    readonly property color fillColor: Qt.rgba(
        root.lowColor.r + (Theme.m3Primary.r - root.lowColor.r) * root.tone,
        root.lowColor.g + (Theme.m3Primary.g - root.lowColor.g) * root.tone,
        root.lowColor.b + (Theme.m3Primary.b - root.lowColor.b) * root.tone,
        1.0
    )
    readonly property color iconColor: root.tone >= 0.5
        ? Theme.m3OnPrimary
        : Theme.iconTint
    // Los iconos del perfil salen del tema activo (ver BarIcons.js).

    implicitWidth: 28
    implicitHeight: 26
    opacity: root.supported ? 1.0 : 0.4

    onProfileChanged: {
        if (root.profile !== root.displayProfile)
            root.displayProfile = root.profile;
    }

    function applyState(doc) {
        if (!doc || typeof doc !== "object")
            return;
        if (Array.isArray(doc.choices))
            root.choices = doc.choices;
        if (typeof doc.backend === "string" && doc.backend !== root.backend) {
            root.backend = doc.backend;
            if (doc.backend === "none")
                console.log("caparazon: sin motor de perfil energético disponible");
        }
        if (typeof doc.profile === "string" && doc.profile.length > 0)
            root.profile = doc.profile;
    }

    function applyProfile(next) {
        if (!next || next === root.displayProfile || !root.supported)
            return;
        root.displayProfile = next;
        Quickshell.execDetached(["caparazon-wm", "power-profile", "--set", next]);
        // La lectura posterior es la que manda: si el motor rechazó el
        // perfil, el chip vuelve al que realmente está activo.
        refresh.restart();
    }

    function cycle(step) {
        if (!root.supported)
            return;
        let index = root.choices.indexOf(root.displayProfile);
        if (index < 0)
            index = 0;

        const next = root.choices[
            (index + step + root.choices.length) % root.choices.length
        ];
        root.applyProfile(next);
    }

    Process {
        id: query
        command: ["caparazon-wm", "power-profile"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyState(JSON.parse(text));
                } catch (e) {
                    console.log("caparazon: fallo al parsear el perfil energético:", e);
                }
            }
        }
    }

    Timer {
        id: refresh
        interval: 250
        onTriggered: {
            query.running = false;
            query.running = true;
        }
    }

    Component.onCompleted: {
        if (!query.running)
            query.running = true;
    }

    // Mismo círculo de fondo que el resto de indicadores de estado.
    Rectangle {
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: width / 2
        color: hover.hovered
            ? (root.tone > 0
                ? Qt.lighter(root.fillColor, 1.08)
                : Qt.lighter(Theme.chipHover, 1.45))
            : root.fillColor

        Behavior on color {
            ColorAnimation { duration: Theme.dur; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: IconResolver.firstOf(BarIcons.powerProfileNames(root.displayProfile))
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.iconColor
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        enabled: root.supported
        cursorShape: Qt.PointingHandCursor
        onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0)
                root.cycle(1);
            else if (wheel.angleDelta.y < 0)
                root.cycle(-1);
        }
    }
}

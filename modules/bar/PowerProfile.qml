import Quickshell
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

    property string profile: "balanced"
    property string displayProfile: profile

    readonly property var profiles: ["power-saver", "balanced", "performance"]

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
        : Theme.text
    // Los iconos del perfil salen del tema activo (ver BarIcons.js).

    implicitWidth: 28
    implicitHeight: 26

    onProfileChanged: {
        if (root.profile !== root.displayProfile)
            root.displayProfile = root.profile;
    }

    function applyProfile(next) {
        if (!next || next === root.displayProfile)
            return;
        root.displayProfile = next;
        Quickshell.execDetached([
            "qdbus6",
            "org.kde.Solid.PowerManagement",
            "/org/kde/Solid/PowerManagement/Actions/PowerProfile",
            "org.kde.Solid.PowerManagement.Actions.PowerProfile.setProfile",
            next
        ]);
    }

    function cycle(step) {
        let index = root.profiles.indexOf(root.displayProfile);
        if (index < 0)
            index = 1;

        const next = root.profiles[
            (index + step + root.profiles.length) % root.profiles.length
        ];
        root.applyProfile(next);
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
        cursorShape: Qt.PointingHandCursor
        onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0)
                root.cycle(1);
            else if (wheel.angleDelta.y < 0)
                root.cycle(-1);
        }
    }
}

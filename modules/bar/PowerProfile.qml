import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"

// Selector compacto del perfil de energía. La rueda del mouse cambia entre
// ahorro, equilibrado y rendimiento sin abrir ningún menú.
Item {
    id: root

    property string profile: "balanced"
    property string displayProfile: profile

    readonly property var profiles: ["power-saver", "balanced", "performance"]
    readonly property string iconName: {
        if (root.displayProfile === "performance")
            return "power-profile-performance-symbolic";
        if (root.displayProfile === "power-saver")
            return "power-profile-power-saver-symbolic";
        return "power-profile-balanced-symbolic";
    }

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
            ? Qt.lighter(Theme.chipHover, 1.45)
            : Qt.lighter(Theme.chipHover, 1.3)

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: Quickshell.iconPath(root.iconName, "power-profile-balanced-symbolic")
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Theme.text
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

import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../../theme"

// Pager de escritorios virtuales de KWin.
// KWin no expone ext-workspace, así que vamos por DBus:
//   - estado: busctl --json=short (JSON limpio, parseable con JSON.parse)
//   - cambios en vivo: dbus-monitor escuchando la interfaz de KWin
//   - cambiar: org.kde.KWin.setCurrentDesktop(int) (1-based)
Row {
    id: root

    visible: true
    spacing: 4

    property var service: null
    property string screenName: ""

    readonly property var desks: service ? service.desks : []
    readonly property var occupiedIds: service ? service.occupiedIds(root.screenName) : []
    readonly property bool occupancyKnown: service ? service.occupancyKnown : false
    readonly property string screenCurrentId: service ? service.screenCurrentId(root.screenName) : ""
    readonly property bool screenFocused: service ? service.screenFocused(root.screenName) : true

    // Números en kanji (1-99): 1 → 一, 10 → 十, 21 → 二十一.
    function kanji(n) {
        const d = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"];
        if (n <= 0 || n > 99)
            return String(n);
        if (n < 10)
            return d[n];
        const tens = Math.floor(n / 10);
        const ones = n % 10;
        return (tens === 1 ? "" : d[tens]) + "十" + (ones ? d[ones] : "");
    }

    Repeater {
        model: root.desks

        delegate: Item {
            id: pill
            required property var modelData

            readonly property bool active: modelData.id === root.screenCurrentId
            readonly property bool hasApps: root.occupancyKnown
                && root.occupiedIds.indexOf(modelData.id) !== -1
            readonly property color activeColor: root.screenFocused
                ? Theme.m3Primary
                : Theme.text

            width: 26
            height: 26

            // Mismo círculo de fondo que el resto de iconos de la barra.
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.lighter(Theme.chipHover, 1.3)
            }

            // Halo activo: degradado radial dentro del círculo, sin desbordar.
            Shape {
                anchors.fill: parent
                visible: pill.active && root.screenFocused
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: 13
                        centerY: 13
                        centerRadius: 0
                        focalX: 13
                        focalY: 13
                        focalRadius: 13

                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(Theme.glowColor.r, Theme.glowColor.g, Theme.glowColor.b, 0.55)
                        }
                        GradientStop {
                            position: 0.55
                            color: Qt.rgba(Theme.glowColor.r, Theme.glowColor.g, Theme.glowColor.b, 0.18)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(Theme.glowColor.r, Theme.glowColor.g, Theme.glowColor.b, 0.0)
                        }
                    }

                    startX: 13
                    startY: 0

                    PathAngleArc {
                        centerX: 13
                        centerY: 13
                        radiusX: 13
                        radiusY: 13
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }

            // Número nítido.
            Text {
                id: num
                anchors.centerIn: parent
                text: root.kanji(pill.modelData.pos + 1)
                color: pill.active
                    ? pill.activeColor
                    : (root.occupancyKnown && !pill.hasApps
                        ? Qt.darker(Theme.textDim, 1.6)
                        : Theme.textDim)
                font.family: Theme.fontJP
                font.pixelSize: 15
                font.weight: Font.Bold
                font.hintingPreference: Font.PreferFullHinting
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached([
                    "qdbus6", "org.kde.KWin", "/KWin",
                    "org.kde.KWin.setCurrentDesktop",
                    String(pill.modelData.pos + 1)
                ])
            }
        }
    }
}

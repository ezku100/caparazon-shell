import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Shapes
import "../../components"
import "../../theme"

// Chip de audio reutilizable para altavoz y micrófono.
// Clic = mute, rueda = volumen. El medidor rodea el icono sin moverlo.
HoverChip {
    id: root

    property var audioNode: null
    property bool microphone: false

    property real level: audioNode && audioNode.audio ? audioNode.audio.volume : 0
    property bool muted: audioNode && audioNode.audio ? audioNode.audio.muted : false

    readonly property bool overdriven: !root.muted && root.level > 1.0001
    readonly property real meterValue: root.muted
        ? 0
        : Math.max(0, Math.min(1, root.level))
    // La segunda vuelta cubre el rango 100–150 %.
    readonly property real overdriveValue: root.overdriven
        ? Math.max(0, Math.min(1, (root.level - 1) / 0.5))
        : 0
    readonly property color overdriveColor: Qt.darker(Theme.m3Primary, 1.6)

    readonly property string iconGlyph: root.microphone
        ? (root.muted || root.level <= 0.001 ? "\u{F036D}" : "\u{F036C}")
        : (root.muted || root.level <= 0.001 ? "\u{F0581}"
            : root.level < 0.40 ? "\u{F0580}"
            : root.level < 0.75 ? "\u{F057F}"
            : "\u{F057E}")

    // El chip conserva su tamaño (28×26) para no desplazar nada.
    radius: 13

    PwObjectTracker {
        objects: root.audioNode ? [root.audioNode] : []
    }

    Item {
        anchors.centerIn: parent
        width: 26
        height: 26

        Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 2
                strokeColor: Theme.hairline
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: 13
                    centerY: 13
                    radiusX: 12
                    radiusY: 12
                    startAngle: -90
                    sweepAngle: 360
                }
            }

            ShapePath {
                strokeWidth: 2
                strokeColor: Theme.m3Primary
                fillColor: "transparent"
                capStyle: root.meterValue > 0
                    ? ShapePath.RoundCap
                    : ShapePath.FlatCap

                PathAngleArc {
                    centerX: 13
                    centerY: 13
                    radiusX: 12
                    radiusY: 12
                    startAngle: -90
                    sweepAngle: 360 * root.meterValue
                }
            }

            // Segunda vuelta, más oscura, para el exceso sobre 100 %.
            ShapePath {
                strokeWidth: 2
                strokeColor: root.overdriveColor
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: 13
                    centerY: 13
                    radiusX: 12
                    radiusY: 12
                    startAngle: -90
                    sweepAngle: 360 * root.overdriveValue
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        color: root.muted ? Theme.textDim : Theme.text
        font.family: Theme.fontIcon
        font.pixelSize: 15
        text: root.iconGlyph
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (root.audioNode && root.audioNode.audio)
                root.audioNode.audio.muted = !root.audioNode.audio.muted;
        }

        onWheel: function (wheel) {
            if (!root.audioNode || !root.audioNode.audio)
                return;
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
            root.audioNode.audio.volume =
                Math.max(0, Math.min(1.5, root.audioNode.audio.volume + step));
        }
    }
}

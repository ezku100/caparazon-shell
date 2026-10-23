import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../../theme"

// Icono dentro de un anillo de progreso o de un círculo de fondo.
Item {
    id: root

    property real value: 0
    property string label: ""
    property string iconName: ""
    property string iconSource: ""
    property color progressColor: Theme.m3Primary
    property bool showRing: true
    property bool filledBackground: false
    property color backgroundColor: "transparent"
    property bool wheelEnabled: false
    property bool tipVisible: false

    signal wheelUp()
    signal wheelDown()

    readonly property string tipText: root.label !== ""
        ? root.label + " " + Math.round(root.value) + "%"
        : ""

    readonly property string resolvedIconSource: root.iconSource !== ""
        ? root.iconSource
        : (root.iconName !== ""
            ? Quickshell.iconPath(root.iconName, "application-x-executable")
            : "")

    implicitWidth: 28
    implicitHeight: 28

    Rectangle {
        anchors.centerIn: parent
        width: root.width - 2
        height: root.height - 2
        visible: root.filledBackground
        radius: width / 2
        color: root.backgroundColor
    }

    Shape {
        anchors.fill: parent
        visible: root.showRing
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 2
            strokeColor: Theme.hairline
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - 2
                radiusY: root.height / 2 - 2
                startAngle: -90
                sweepAngle: 360
            }
        }

        ShapePath {
            strokeWidth: 2
            strokeColor: root.progressColor
            fillColor: "transparent"
            capStyle: root.value > 0 ? ShapePath.RoundCap : ShapePath.FlatCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - 2
                radiusY: root.height / 2 - 2
                startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(1, root.value / 100))
            }
        }
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 14
        source: root.resolvedIconSource
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Theme.text
        }
    }

    Timer {
        id: tipDelay
        interval: 350
        repeat: false
        onTriggered: root.tipVisible = true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tipDelay.restart()
        onExited: {
            tipDelay.stop();
            root.tipVisible = false;
        }
        onWheel: function(wheel) {
            if (!root.wheelEnabled)
                return;
            if (wheel.angleDelta.y > 0)
                root.wheelUp();
            else if (wheel.angleDelta.y < 0)
                root.wheelDown();
        }
    }

    PopupWindow {
        id: tip
        visible: root.tipVisible && root.tipText !== ""
        color: "transparent"
        grabFocus: false

        readonly property int bleed: 14
        readonly property int arrowW: 16
        readonly property int arrowH: 8
        readonly property int bodyWidth: Math.max(96, tipText.implicitWidth + 28)
        readonly property int bodyHeight: 36

        anchor.item: root
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Bottom
        anchor.adjustment: PopupAdjustment.SlideX
        anchor.rect.x: Math.round(root.width / 2)
        // Igual que TrayMenu: el pico de la cola debe tocar el borde de la barra.
        anchor.rect.y: Math.round((Theme.barHeight + root.height) / 2 + 6)
        anchor.rect.width: 1
        anchor.rect.height: 1

        implicitWidth: bodyWidth + bleed * 2
        // El bleed inferior evita que se recorte la sombra de la burbuja.
        implicitHeight: arrowH - 1 + bodyHeight + bleed

        mask: Region { item: bubble }

        Item {
            id: body
            x: tip.bleed
            y: tip.arrowH - 1
            width: tip.bodyWidth
            height: tip.bodyHeight

            MultiEffect {
                source: bubble
                anchors.fill: bubble
                blurMax: 24
                shadowEnabled: true
                shadowColor: Theme.shadowColor
                shadowOpacity: 0.20
                shadowBlur: 0.32
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 3
            }

            Rectangle {
                id: bubble
                anchors.fill: parent
                radius: 16
                color: Theme.surface
            }

            Text {
                id: tipText
                anchors.centerIn: parent
                width: implicitWidth
                text: root.tipText
                color: Theme.m3OnSurface
                font.family: Theme.fontUI
                font.pixelSize: 13
                font.weight: Font.Medium
                wrapMode: Text.NoWrap
                elide: Text.ElideNone
                textFormat: Text.PlainText
            }
        }

        // Cola superior: misma silueta y relleno que la burbuja.
        Shape {
            // Debajo de la burbuja para que no tape el texto.
            // -6 compensa el desplazamiento visual que introduce el bleed del popup.
            z: -1
            x: Math.round(tip.bleed + tip.bodyWidth / 2 - tip.arrowW / 2 - 6)
            y: 0
            width: tip.arrowW
            height: tip.arrowH + 1
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: bubble.color
                startX: 0
                startY: height
                PathLine { x: width / 2; y: 0 }
                PathLine { x: width; y: height }
                PathLine { x: 0; y: height }
            }
        }
    }
}

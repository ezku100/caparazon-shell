import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../../theme"
import "../icons"

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
    // Barra abajo: el globo abre hacia arriba, con la cola hacia abajo.
    property bool tipAbove: false

    // Unidad del globo de ayuda: los medidores de uso van en %, la
    // temperatura en grados.
    property string unit: "%"

    signal wheelUp()
    signal wheelDown()

    readonly property string tipText: root.label !== ""
        ? root.label + " " + Math.round(root.value) + root.unit
        : ""

    readonly property string resolvedIconSource: root.iconSource !== ""
        ? root.iconSource
        : (root.iconName !== ""
            ? IconResolver.source(root.iconName, "application-x-executable")
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
            colorizationColor: Theme.iconTint
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

    Loader {
        active: root.tipVisible && root.tipText !== ""
        sourceComponent: PopupWindow {
            id: tip
            visible: true
            color: "transparent"
            grabFocus: false

            readonly property int bleed: 14
            readonly property int bodyWidth: Math.max(96, tipText.implicitWidth + 28)
            readonly property int bodyHeight: 36

            anchor.item: root
            anchor.edges: root.tipAbove ? Edges.Bottom : Edges.Top
            anchor.gravity: root.tipAbove ? Edges.Top : Edges.Bottom
            anchor.adjustment: PopupAdjustment.SlideX
            anchor.rect.x: Math.round(root.width / 2)
            // Sin cola: la burbuja flota junto al borde de la barra. Arriba:
            // el borde inferior de la barra en coordenadas del anillo; abajo:
            // el superior (espejado). El +6 deja un aire mínimo contra la barra.
            anchor.rect.y: root.tipAbove
                ? -(Theme.barHeight - root.height) / 2 - 6
                : Math.round((Theme.barHeight + root.height) / 2 + 6)
            anchor.rect.width: 1
            anchor.rect.height: 1

            implicitWidth: bodyWidth + bleed * 2
            // Aire simétrico: la sombra cabe en ambos bordes.
            implicitHeight: bodyHeight + bleed * 2

            mask: Region { item: bubble }

            Item {
                id: body
                x: tip.bleed
                y: tip.bleed
                width: tip.bodyWidth
                height: tip.bodyHeight

                // Sombra hacia dentro de la pantalla en ambos bordes.
                MultiEffect {
                    source: bubble
                    anchors.fill: bubble
                    blurMax: 24
                    shadowEnabled: true
                    shadowColor: Theme.shadowColor
                    shadowOpacity: 0.20
                    shadowBlur: 0.32
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: root.tipAbove ? -3 : 3
                }

                // Globo de texto: burbuja simple sin cola, centrada sobre el
                // anillo. Se adapta igual a la barra arriba o abajo.
                Rectangle {
                    id: bubble
                    anchors.fill: parent
                    radius: 16
                    color: Theme.surface
                }

                Text {
                    id: tipText
                    anchors.centerIn: parent
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
        }
    }
}

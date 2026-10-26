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

    Loader {
        active: root.tipVisible && root.tipText !== ""
        sourceComponent: PopupWindow {
            id: tip
            visible: true
            color: "transparent"
            grabFocus: false

            readonly property int bleed: 14
            readonly property int arrowW: 18
            readonly property int arrowH: 8
            readonly property int bubbleRadius: 16
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
            // El bleed inferior evita que se recorte la sombra del globo.
            implicitHeight: arrowH + bodyHeight + bleed

            mask: Region { item: balloon }

            Item {
                id: body
                x: tip.bleed
                y: 0
                width: tip.bodyWidth
                height: tip.arrowH + tip.bodyHeight

                // Sombra: se proyecta desde la silueta completa (cuerpo + cola).
                MultiEffect {
                    source: balloon
                    anchors.fill: balloon
                    blurMax: 24
                    shadowEnabled: true
                    shadowColor: Theme.shadowColor
                    shadowOpacity: 0.20
                    shadowBlur: 0.32
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 3
                }

                // Globo de texto: un solo contorno (rectángulo redondeado + cola
                // centrada con la punta suavizada), sin costuras entre piezas.
                // Dentro de un ShapePath, "width"/"height" sin prefijo NO son los
                // del Shape, así que todo se calcula desde balloonPath.
                Shape {
                    id: balloon
                    anchors.fill: parent
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        id: balloonPath
                        readonly property real w: tip.bodyWidth
                        readonly property real h: tip.bodyHeight
                        readonly property real a: tip.arrowH
                        readonly property real tw: tip.arrowW
                        readonly property real r: tip.bubbleRadius
                        readonly property real cx: w / 2

                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Theme.surface

                        startX: r
                        startY: a

                        // borde superior hasta la base de la cola
                        PathLine { x: balloonPath.cx - balloonPath.tw / 2; y: balloonPath.a }

                        // cola: lados a 45° y punta redondeada
                        PathLine { x: balloonPath.cx - 2.2; y: 1.4 }
                        PathQuad {
                            x: balloonPath.cx + 2.2
                            y: 1.4
                            controlX: balloonPath.cx
                            controlY: -0.9
                        }
                        PathLine { x: balloonPath.cx + balloonPath.tw / 2; y: balloonPath.a }

                        // resto del borde superior
                        PathLine { x: balloonPath.w - balloonPath.r; y: balloonPath.a }

                        // superior derecha
                        PathArc {
                            x: balloonPath.w
                            y: balloonPath.a + balloonPath.r
                            radiusX: balloonPath.r
                            radiusY: balloonPath.r
                            direction: PathArc.Clockwise
                            useLargeArc: false
                        }

                        // lado derecho
                        PathLine { x: balloonPath.w; y: balloonPath.a + balloonPath.h - balloonPath.r }

                        // inferior derecha
                        PathArc {
                            x: balloonPath.w - balloonPath.r
                            y: balloonPath.a + balloonPath.h
                            radiusX: balloonPath.r
                            radiusY: balloonPath.r
                            direction: PathArc.Clockwise
                            useLargeArc: false
                        }

                        // borde inferior
                        PathLine { x: balloonPath.r; y: balloonPath.a + balloonPath.h }

                        // inferior izquierda
                        PathArc {
                            x: 0
                            y: balloonPath.a + balloonPath.h - balloonPath.r
                            radiusX: balloonPath.r
                            radiusY: balloonPath.r
                            direction: PathArc.Clockwise
                            useLargeArc: false
                        }

                        // lado izquierdo
                        PathLine { x: 0; y: balloonPath.a + balloonPath.r }

                        // superior izquierda (cierra en el punto de inicio)
                        PathArc {
                            x: balloonPath.r
                            y: balloonPath.a
                            radiusX: balloonPath.r
                            radiusY: balloonPath.r
                            direction: PathArc.Clockwise
                            useLargeArc: false
                        }
                    }
                }

                Text {
                    id: tipText
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: tip.arrowH + Math.round((tip.bodyHeight - height) / 2)
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
        }
    }
}

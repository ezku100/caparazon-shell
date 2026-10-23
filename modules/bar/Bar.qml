import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../../theme"
import "../../components"

// Caparazón — barra superior.
// Panel layer-shell anclado arriba, forma "nacida del borde" y acabado
// SÓLIDO tipo Material (sin blur).
PanelWindow {
    id: bar

    required property var modelData
    screen: modelData
    property var trayMenuState: null
    property var notificationServer: null
    property string activeWindowAppId: ""
    property string activeWindowTitle: ""
    property int cpuUsage: 0
    property int ramUsage: 0
    property int gpuUsage: 0
    property int swapUsage: 0
    property int networkUsage: 0
    property string networkIcon: "network-wired"
    property string powerProfile: "balanced"

    readonly property var activeTrayMenu: trayMenuState ? trayMenuState.active : null

    // En pantallas angostas (por ejemplo el monitor vertical de 1080 px) los
    // seis anillos no caben entre el reloj y la bandeja sin tapar el reloj.
    // Se ocultan ahí; la bandeja conserva su sitio y el resto sigue igual.
    readonly property bool compactBar: bar.screen ? bar.screen.width < 1400 : false

    function closeTrayMenu() {
        if (!activeTrayMenu)
            return;
        const top = typeof activeTrayMenu.topMenu === "function"
            ? activeTrayMenu.topMenu()
            : activeTrayMenu;
        top.close();
    }

    // Barra FLOTANTE: no abarca todo el ancho. Márgenes laterales simétricos
    // => queda centrada y pegada al borde superior (de ahí "nace").
    readonly property int sideMargin: Math.round(((screen ? screen.width : 1920) * (1 - Theme.barWidthFrac)) / 2)

    anchors { top: true; left: true; right: true }
    // La ventana es más ancha que la barra por shadowPad: ese aire alberga
    // la sombra. Los márgenes laterales se descuentan para que la barra
    // visible siga midiendo exactamente barWidthFrac del monitor.
    margins {
        top: 0
        left: bar.sideMargin - Theme.shadowPad
        right: bar.sideMargin - Theme.shadowPad
    }

    // Acabado SÓLIDO tipo Material 3 (sin blur ni borde): superficie opaca.
    // El alto incluye el aire inferior de la sombra; exclusiveZone reserva
    // sólo la franja de la barra para el resto de ventanas.
    implicitHeight: Theme.barHeight + Theme.shadowPad
    exclusiveZone: Theme.barHeight
    color: "transparent"

    // La zona de sombra no debe tragarse clics: sólo la barra es clicable.
    mask: Region { item: hitArea }
    Item {
        id: hitArea
        x: Theme.shadowPad
        y: 0
        width: parent.width - 2 * Theme.shadowPad
        height: Theme.barHeight

    }

    // Efecto entrada: "nace del borde superior". La barra se destapa de
    // arriba hacia abajo (crece desde el borde) con un leve fundido.
    property real reveal: 0
    Component.onCompleted: reveal = 1
    Behavior on reveal {
        NumberAnimation { duration: 460; easing.type: Easing.OutCubic }
    }

    Item {
        id: frame
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: bar.reveal * (Theme.barHeight + Theme.shadowPad)
        clip: true
        opacity: 0.25 + 0.75 * bar.reveal

        // Sombra de elevación: se dibuja antes que el vidrio, así que queda
        // detrás. El MultiEffect repinta la silueta (idéntica y tapada por
        // el Shape) y proyecta la sombra difusa fuera de sus límites.
        MultiEffect {
            id: elevation
            source: glass
            anchors { left: parent.left; leftMargin: Theme.shadowPad; top: parent.top }
            width: parent.width - 2 * Theme.shadowPad
            height: Theme.barHeight

            blurMax: 32
            shadowEnabled: true
            shadowColor: Theme.shadowColor
            shadowOpacity: Theme.shadowOpacity
            shadowBlur: Theme.shadowBlur
            shadowHorizontalOffset: 0
            shadowVerticalOffset: Theme.shadowOffsetY
        }

        // Vidrio "nacido del borde": el borde superior llega hasta el filo
        // de la pantalla y las esquinas SUPERIORES se vacían hacia dentro
        // (curva cóncava), dejando el labio que se abre hacia fuera.
        // Las esquinas inferiores siguen convexas.
        Shape {
            id: glass
            antialiasing: true   // suaviza el contorno de las curvas y el borde
            preferredRendererType: Shape.CurveRenderer   // curvas con AA de alta calidad
            anchors {
                left: parent.left; leftMargin: Theme.shadowPad
                right: parent.right; rightMargin: Theme.shadowPad
                top: parent.top
            }
            height: Theme.barHeight

            ShapePath {
                id: glassPath
                readonly property int rt: Theme.radiusTop
                readonly property int rb: Theme.radius

                // Sin borde: la silueta la define el contraste de la
                // superficie contra el fondo (estilo Material 3).
                strokeWidth: 0
                strokeColor: "transparent"

                // Superficie Material 3 sólida (token surfaceContainer).
                fillColor: Theme.surface

                startX: 0
                startY: 0

                // borde superior (pegado al filo de la pantalla)
                PathLine { x: glass.width; y: 0 }

                // superior derecha: se vacía hacia dentro
                PathArc {
                    x: glass.width - glassPath.rt
                    y: glassPath.rt
                    radiusX: glassPath.rt
                    radiusY: glassPath.rt
                    direction: PathArc.Counterclockwise
                    useLargeArc: false
                }

                // lado derecho
                PathLine { x: glass.width - glassPath.rt; y: glass.height - glassPath.rb }

                // inferior derecha: convexa
                PathArc {
                    x: glass.width - glassPath.rt - glassPath.rb
                    y: glass.height
                    radiusX: glassPath.rb
                    radiusY: glassPath.rb
                    direction: PathArc.Clockwise
                    useLargeArc: false
                }

                // borde inferior
                PathLine { x: glassPath.rt + glassPath.rb; y: glass.height }

                // inferior izquierda: convexa
                PathArc {
                    x: glassPath.rt
                    y: glass.height - glassPath.rb
                    radiusX: glassPath.rb
                    radiusY: glassPath.rb
                    direction: PathArc.Clockwise
                    useLargeArc: false
                }

                // lado izquierdo
                PathLine { x: glassPath.rt; y: glassPath.rt }

                // superior izquierda: se vacía hacia dentro
                PathArc {
                    x: 0
                    y: 0
                    radiusX: glassPath.rt
                    radiusY: glassPath.rt
                    direction: PathArc.Counterclockwise
                    useLargeArc: false
                }
            }

            // ── Izquierda: escritorios + ventana activa ────────────────
            // Módulos independientes: el selector queda anclado a la
            // izquierda y la ventana activa crece hacia la derecha sin
            // desplazarlo.
            Workspaces {
                id: workspaces
                screenName: bar.screen ? bar.screen.name : ""
                anchors {
                    left: parent.left; leftMargin: Theme.padH + Theme.radiusTop
                    verticalCenter: parent.verticalCenter
                }
            }

            ActiveWindow {
                anchors {
                    left: workspaces.right; leftMargin: 20
                    verticalCenter: parent.verticalCenter
                }
                appId: bar.activeWindowAppId
                title: bar.activeWindowTitle
                compact: bar.compactBar
            }

            // ── Centro: reloj + notificación activa ──────────────────
            // El grupo completo se centra. Al entrar una notificación, el
            // reloj corre hacia escritorios y el chip aparece a su derecha.
            Row {
                id: centerCluster
                anchors.centerIn: parent
                spacing: 8

                Clock { compact: bar.compactBar }
                NotificationChip { server: bar.notificationServer }
                MediaChip {}
            }

            // ── Derecha: recursos + bandeja + red + volumen ───────────
            // El monitor se ancla por separado para que al cambiar su
            // contenido no mueva la bandeja.
            ResourceMonitor {
                visible: !bar.compactBar
                anchors {
                    right: rightCluster.left; rightMargin: 16
                    verticalCenter: parent.verticalCenter
                }
                cpu: bar.cpuUsage
                ram: bar.ramUsage
                gpu: bar.gpuUsage
                swap: bar.swapUsage
                network: bar.networkUsage
                networkIcon: bar.networkIcon
            }

            Row {
                id: rightCluster
                anchors {
                    right: parent.right; rightMargin: Theme.padH + Theme.radiusTop
                    verticalCenter: parent.verticalCenter
                }
                // Misma separación monitor ↔ bandeja ↔ grupo de red.
                spacing: 16

                Tray {
                    id: tray
                    trayMenuState: bar.trayMenuState
                }

                // Iconos de estado juntos, con su ritmo interno corto.
                Row {
                    spacing: 4

                    Network {}
                    PowerProfile { profile: bar.powerProfile }
                    BluetoothIndicator {}
                    MicVolume {}
                    Volume {}
                    PowerButton {}
                }
            }
        }
    }

    // Barreras modales a los lados de la bandeja: mientras hay un menú
    // abierto, un clic en el resto de la barra lo cierra. La fila de la
    // bandeja queda libre para que un clic en otro icono cierre el menú
    // actual y abra el nuevo en el mismo clic.
    MouseArea {
        x: hitArea.x
        y: 0
        width: Math.max(0, tray.mapToItem(hitArea, 0, 0).x)
        height: hitArea.height
        z: 100
        enabled: bar.trayMenuState !== null && bar.trayMenuState.active !== null
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: bar.closeTrayMenu()
    }

    MouseArea {
        x: hitArea.x + tray.mapToItem(hitArea, 0, 0).x + tray.width
        y: 0
        width: Math.max(0, hitArea.width
            - tray.mapToItem(hitArea, 0, 0).x - tray.width)
        height: hitArea.height
        z: 100
        enabled: bar.trayMenuState !== null && bar.trayMenuState.active !== null
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: bar.closeTrayMenu()
    }

    // Capa modal a pantalla completa para cerrar el menú al pulsar el
    // escritorio o cualquier ventana. Queda por debajo del popup del menú
    // (que sigue recibiendo sus propios clics) y deja un hueco sobre la
    // fila de iconos para no romper el cambio de bandeja en un solo clic.
    PanelWindow {
        id: menuClickCatcher
        screen: bar.screen
        visible: bar.activeTrayMenu !== null
        anchors { top: true; left: true; right: true; bottom: true }
        exclusiveZone: 0
        focusable: false
        color: "transparent"

        mask: Region {
            x: 0
            y: 0
            width: bar.screen ? bar.screen.width : bar.width
            height: bar.screen ? bar.screen.height : bar.height

            Region {
                x: hitArea.x + tray.mapToItem(hitArea, 0, 0).x
                y: 0
                width: tray.width
                height: Theme.barHeight
                intersection: Intersection.Subtract
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: bar.closeTrayMenu()
        }
    }
}

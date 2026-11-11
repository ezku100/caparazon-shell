import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../../theme"
import "../../components"
import "../appmenu"
import "../secondmenu"

// Caparazón — barra superior.
// Panel layer-shell anclado arriba, forma "nacida del borde" y acabado
// SÓLIDO tipo Material (sin blur).
PanelWindow {
    id: bar

    required property var modelData
    screen: modelData
    property var powerMenuState: null
    property var appMenuState: null
    property var secondMenuState: null
    property var clipboardHistory: null
    property var notificationHistory: null
    property var trayMenuState: null
    property var notificationServer: null
    property var workspacesService: null
    property string activeWindowAppId: ""
    // Apagada desde el panel: se oculta, no se destruye (sus menús siguen
    // disponibles desde el dock y los atajos).
    property bool shown: true
    property int cpuUsage: 0
    property int ramUsage: 0
    property int gpuUsage: 0
    property int swapUsage: 0
    property int networkUsage: 0
    property string powerProfile: "balanced"
    property var resources: null

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

    function openAppMenu() {
        closeTrayMenu();
        if (!appMenuState)
            return;
        if (secondMenuState && secondMenuState.opened)
            secondMenuState.close();
        if (appMenuState.opened) {
            appMenuState.close();
            return;
        }
        appMenuState.open(bar.screen);
    }

    // La categoría es opcional: el reloj pide "calendario" y los anillos del
    // monitor "sistema".
    function openSecondMenu(category) {
        closeTrayMenu();
        if (!secondMenuState)
            return;
        if (secondMenuState.opened) {
            secondMenuState.close();
            return;
        }
        secondMenuState.open(bar.screen, category || "calendario");
    }

    function openPowerMenu() {
        closeTrayMenu();
        if (appMenuState && appMenuState.opened)
            appMenuState.close();
        if (powerMenuState)
            powerMenuState.open(bar.screen);
    }

    // Barra FLOTANTE: no abarca todo el ancho. Márgenes laterales simétricos
    // => queda centrada y pegada al borde elegido (de ahí "nace").
    readonly property int sideMargin: Math.round(((screen ? screen.width : 1920) * (1 - Theme.barWidthFrac)) / 2)

    // Borde al que se pega: "top" (por defecto) o "bottom". Todo lo que mira
    // al borde (forma, sombra, entrada, menús de bandeja) se espeja.
    property string position: "top"
    readonly property bool atBottom: bar.position === "bottom"

    anchors { top: !bar.atBottom; bottom: bar.atBottom; left: true; right: true }
    // La ventana es más ancha que la barra por shadowPad: ese aire alberga
    // la sombra. Los márgenes laterales se descuentan para que la barra
    // visible siga midiendo exactamente barWidthFrac del monitor.
    margins {
        top: 0
        bottom: 0
        left: bar.sideMargin - Theme.shadowPad
        right: bar.sideMargin - Theme.shadowPad
    }

    // Acabado SÓLIDO tipo Material 3 (sin blur ni borde): superficie opaca.
    // El alto incluye el aire inferior de la sombra; exclusiveZone reserva
    // sólo la franja de la barra para el resto de ventanas.
    visible: bar.shown
    implicitHeight: Theme.barHeight + Theme.shadowPad
    exclusiveZone: bar.shown ? Theme.barHeight : 0
    color: "transparent"

    // La zona de sombra no debe tragarse clics: sólo la barra es clicable.
    mask: Region { item: hitArea }
    Item {
        id: hitArea
        x: Theme.shadowPad
        y: bar.atBottom ? parent.height - Theme.barHeight : 0
        width: parent.width - 2 * Theme.shadowPad
        height: Theme.barHeight

    }

    // Efecto entrada: "nace del borde". La barra se destapa desde el filo
    // de la pantalla hacia dentro (crece desde el borde) con un leve fundido.
    property real reveal: 0
    Component.onCompleted: reveal = 1
    Behavior on reveal {
        NumberAnimation { duration: 460; easing.type: Easing.OutCubic }
    }

    Item {
        id: frame
        anchors { left: parent.left; right: parent.right }
        // Crece desde el filo: con la barra abajo, su base es el filo inferior.
        y: bar.atBottom ? parent.height - height : 0
        height: bar.reveal * (Theme.barHeight + Theme.shadowPad)
        clip: true
        opacity: 0.25 + 0.75 * bar.reveal

        // Sombra de elevación: se dibuja antes que el vidrio, así que queda
        // detrás. El MultiEffect repinta la silueta (idéntica y tapada por
        // el Shape) y proyecta la sombra difusa fuera de sus límites.
        MultiEffect {
            id: elevation
            source: glass
            anchors { left: parent.left; leftMargin: Theme.shadowPad }
            y: bar.atBottom ? parent.height - height : 0
            width: parent.width - 2 * Theme.shadowPad
            height: Theme.barHeight

            blurMax: 32
            shadowEnabled: true
            shadowColor: Theme.shadowColor
            shadowOpacity: Theme.shadowOpacity
            shadowBlur: Theme.shadowBlur
            shadowHorizontalOffset: 0
            // La sombra cae hacia dentro de la pantalla: al fondo de la barra
            // cuando está arriba y por encima cuando está abajo.
            shadowVerticalOffset: bar.atBottom
                ? -Theme.shadowOffsetY : Theme.shadowOffsetY
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
            }
            y: bar.atBottom ? parent.height - height : 0
            height: Theme.barHeight

            ShapePath {
                id: glassPath
                readonly property int rt: Theme.radiusTop
                readonly property int rb: Theme.radius
                readonly property bool flip: bar.atBottom

                // Con la barra abajo el trazado se espeja en vertical: la
                // curva cóncava ("labio") queda pegada al filo inferior y
                // las convexas arriba. y() e inverse() evitan duplicar el
                // path; espejar invierte también el sentido de cada arco.
                function y(value) { return flip ? glass.height - value : value }
                function inverse(value) {
                    if (!flip)
                        return value;
                    return value === PathArc.Clockwise
                        ? PathArc.Counterclockwise : PathArc.Clockwise;
                }

                // Sin borde: la silueta la define el contraste de la
                // superficie contra el fondo (estilo Material 3).
                strokeWidth: 0
                strokeColor: "transparent"

                // Superficie Material 3 sólida (token surfaceContainer).
                fillColor: Theme.surface

                startX: 0
                startY: glassPath.y(0)

                // borde pegado al filo de la pantalla
                PathLine { x: glass.width; y: glassPath.y(0) }

                // primera esquina del filo: se vacía hacia dentro
                PathArc {
                    x: glass.width - glassPath.rt
                    y: glassPath.y(glassPath.rt)
                    radiusX: glassPath.rt
                    radiusY: glassPath.rt
                    direction: glassPath.inverse(PathArc.Counterclockwise)
                    useLargeArc: false
                }

                // lado derecho
                PathLine {
                    x: glass.width - glassPath.rt
                    y: glassPath.y(glass.height - glassPath.rb)
                }

                // esquina opuesta al filo: convexa
                PathArc {
                    x: glass.width - glassPath.rt - glassPath.rb
                    y: glassPath.y(glass.height)
                    radiusX: glassPath.rb
                    radiusY: glassPath.rb
                    direction: glassPath.inverse(PathArc.Clockwise)
                    useLargeArc: false
                }

                // borde opuesto a la pantalla
                PathLine {
                    x: glassPath.rt + glassPath.rb
                    y: glassPath.y(glass.height)
                }

                // segunda esquina convexa
                PathArc {
                    x: glassPath.rt
                    y: glassPath.y(glass.height - glassPath.rb)
                    radiusX: glassPath.rb
                    radiusY: glassPath.rb
                    direction: glassPath.inverse(PathArc.Clockwise)
                    useLargeArc: false
                }

                // lado izquierdo
                PathLine { x: glassPath.rt; y: glassPath.y(glassPath.rt) }

                // segunda esquina del filo: se vacía hacia dentro
                PathArc {
                    x: 0
                    y: glassPath.y(0)
                    radiusX: glassPath.rt
                    radiusY: glassPath.rt
                    direction: glassPath.inverse(PathArc.Counterclockwise)
                    useLargeArc: false
                }
            }

            // ── Izquierda: escritorios + ventana activa ────────────────
            // Módulos independientes: el selector queda anclado a la
            // izquierda y la ventana activa crece hacia la derecha sin
            // desplazarlo.
            LauncherButton {
                id: launcher
                anchors {
                    left: parent.left; leftMargin: Theme.padH + Theme.radiusTop
                    verticalCenter: parent.verticalCenter
                }
                onActivated: bar.openAppMenu()
            }

            Workspaces {
                id: workspaces
                visible: true
                screenName: bar.screen ? bar.screen.name : ""
                service: bar.workspacesService
                anchors {
                    left: launcher.right; leftMargin: 14
                    verticalCenter: parent.verticalCenter
                }
            }

            ActiveWindow {
                anchors {
                    left: workspaces.right; leftMargin: 20
                    verticalCenter: parent.verticalCenter
                }
                appId: bar.activeWindowAppId
                compact: bar.compactBar
            }

            // ── Centro: actualización + reloj + notificación activa ──
            // El grupo completo se centra. Al entrar una actualización o
            // una notificación, el reloj corre y el chip aparece a su lado.
            Row {
                id: centerCluster
                anchors.centerIn: parent
                spacing: 8

                UpdateChip {
                    onActivated: bar.openSecondMenu("configs")
                }
                Clock { compact: bar.compactBar; onActivated: bar.openSecondMenu() }
                NotificationChip { server: bar.notificationServer }
                MediaChip {}
            }

            // ── Derecha: recursos + bandeja + red + volumen ───────────
            // El monitor se ancla por separado para que al cambiar su
            // contenido no mueva la bandeja.
            // En pantallas angostas (barra compacta) los anillos no caben
            // junto al reloj, así que aparecen sólo cuando la bandeja está
            // plegada: ocupan el hueco que ésta deja libre. Se ven los que
            // estén activos en el panel del monitor del sistema.
            ResourceMonitor {
                id: resourceMonitor

                readonly property bool ringsShown:
                    !bar.compactBar || tray.collapsed

                visible: opacity > 0
                opacity: ringsShown ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.durFast + 60
                        easing.type: Easing.OutCubic
                    }
                }

                transform: Translate {
                    x: resourceMonitor.ringsShown ? 0 : 10

                    Behavior on x {
                        NumberAnimation {
                            duration: Theme.durFast + 60
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                anchors {
                    right: rightCluster.left; rightMargin: 16
                    verticalCenter: parent.verticalCenter
                }
                cpu: bar.cpuUsage
                ram: bar.ramUsage
                gpu: bar.gpuUsage
                swap: bar.swapUsage
                network: bar.networkUsage
                temperature: bar.resources ? bar.resources.temperature : 0
                resources: bar.resources
                onActivated: bar.openSecondMenu("sistema")
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
                    menusAbove: bar.atBottom
                }

                // Iconos de estado juntos, con su ritmo interno corto.
                Row {
                    spacing: 4

                    Network {}
                    PowerProfile { profile: bar.powerProfile }
                    BluetoothIndicator {}
                    MicVolume {}
                    Volume {}
                    PowerButton {
                        onActivated: bar.openPowerMenu()
                    }
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
        y: hitArea.y
        width: Math.max(0, tray.mapToItem(hitArea, 0, 0).x)
        height: hitArea.height
        z: 100
        enabled: bar.trayMenuState !== null && bar.trayMenuState.active !== null
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: bar.closeTrayMenu()
    }

    MouseArea {
        x: hitArea.x + tray.mapToItem(hitArea, 0, 0).x + tray.width
        y: hitArea.y
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
    Loader {
        active: bar.activeTrayMenu !== null
        sourceComponent: PanelWindow {
            id: menuClickCatcher
            screen: bar.screen
            visible: true
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
                    y: bar.atBottom
                        ? (bar.screen ? bar.screen.height : bar.height) - Theme.barHeight
                        : 0
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

    Loader {
        // La ventana del menu de sesion se monta siempre: si el Loader
        // la recreara al abrir, el componente naceria ya en reposo y sus
        // Behavior de entrada no tendrian nada que animar. El menu decide
        // cuando mapearse con su propiedad visible.
        active: true
        sourceComponent: PowerMenu {
            screen: bar.screen
            menuState: bar.powerMenuState
        }
    }

    Loader {
        active: true
        sourceComponent: AppMenu {
            screen: bar.screen
            menuState: bar.appMenuState
            clipboardHistory: bar.clipboardHistory
        }
    }

    Loader {
        active: true
        sourceComponent: SecondMenu {
            screen: bar.screen
            menuState: bar.secondMenuState
            notificationHistory: bar.notificationHistory
            cpuUsage: bar.cpuUsage
            ramUsage: bar.ramUsage
            gpuUsage: bar.gpuUsage
            swapUsage: bar.swapUsage
            networkUsage: bar.networkUsage
            temperature: bar.resources ? bar.resources.temperature : 0
            metricSamples: bar.resources ? bar.resources.samples : []
            resources: bar.resources
        }
    }
}

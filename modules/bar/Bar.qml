import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../appmenu"
import "../secondmenu"
import "BarSmartHide.js" as BarSmartHide

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

    // Aire de los extremos en la barra horizontal: el labio del trazo deja
    // la pared visible radiusTop px dentro del frame y el aire de la sombra
    // suma shadowPad; sin descontarlos el lanzador y el botón de apagado
    // quedaban a 2 px del filo.
    readonly property int edgeMargin: Theme.shadowPad + Theme.radiusTop + Theme.padH

    // Borde al que se pega: "top" (por defecto), "bottom", "left" o "right".
    // Todo lo que mira al borde (forma, sombra, entrada) se espeja. En los
    // laterales la barra es vertical: mismo grosor y todo el alto.
    property string position: "top"
    // Anclada: siempre visible y reservando su franja (comportamiento de
    // siempre). Dinámica: oculta hasta que el ratón toca el filo del borde
    // y se aparta al dejarla, igual que el dock. Se elige en Configs.
    property bool anchored: true
    property bool pointerOnBar: false
    // Con el puntero fuera no se retira de golpe: se marca y la gracia decide.
    property bool pointerLeft: false
    // Con un menú abierto la barra no se aparta aunque el ratón salga.
    readonly property bool menuOpen: (secondMenuState && secondMenuState.opened)
        || (powerMenuState && powerMenuState.opened)
        || (appMenuState && appMenuState.opened)
        || bar.activeTrayMenu !== null
    readonly property string smartState:
        BarSmartHide.stateFor(bar.anchored, bar.pointerOnBar)
    readonly property bool wantsReveal:
        bar.shown && (bar.anchored || bar.smartState === "revealed")

    readonly property bool atBottom: bar.position === "bottom"
    readonly property bool atLeft: bar.position === "left"
    readonly property bool atRight: bar.position === "right"
    readonly property bool vertical: bar.atLeft || bar.atRight
    // Bandeja activa según la orientación: la de la fila o la de la columna.
    readonly property var activeTray: bar.vertical ? trayV : tray

    anchors {
        top: bar.vertical ? true : !bar.atBottom
        bottom: bar.vertical ? true : bar.atBottom
        left: bar.vertical ? bar.atLeft : true
        right: bar.vertical ? bar.atRight : true
    }
    // La ventana es más ancha que la barra por shadowPad: ese aire alberga
    // la sombra. Los márgenes laterales se descuentan para que la barra
    // visible siga midiendo exactamente barWidthFrac del monitor.
    margins {
        top: 0
        bottom: 0
        left: bar.atLeft ? 0 : bar.sideMargin - Theme.shadowPad
        right: bar.atRight ? 0 : bar.sideMargin - Theme.shadowPad
    }

    // Acabado SÓLIDO tipo Material 3 (sin blur ni borde): superficie opaca.
    // El alto incluye el aire inferior de la sombra; exclusiveZone reserva
    // sólo la franja de la barra para el resto de ventanas.
    visible: bar.shown
    // Horizontal: 40 px de alto más el aire de la sombra. Vertical: 40 px de
    // ancho (mismo grosor) y todo el alto del monitor.
    implicitWidth: bar.vertical
        ? Theme.barHeight + Theme.shadowPad
        : (screen ? screen.width : 0)
    implicitHeight: bar.vertical
        ? (screen ? screen.height : 0)
        : Theme.barHeight + Theme.shadowPad
    // Dinámica y oculta no reserva franja: las ventanas llegan al borde.
    exclusiveZone: bar.shown
        ? BarSmartHide.exclusiveZone(bar.anchored, Theme.barHeight)
        : 0
    color: "transparent"

    // La zona de sombra no debe tragarse clics: sólo la barra es clicable.
    // Oculta, la ventana sólo acepta el puntero en una franja del filo: así
    // se puede volver a llamar sin que la barra tape nada.
    mask: Region { item: hitArea }
    Item {
        id: hitArea
        // La ventana mide el largo del borde y, en el eje corto, el grosor
        // de la barra más el aire de la sombra.
        readonly property var rect: BarSmartHide.maskRect(bar.smartState, {
            position: bar.position,
            surfaceWidth: bar.vertical
                ? Theme.barHeight + Theme.shadowPad
                : (bar.screen ? bar.screen.width : bar.width),
            surfaceHeight: bar.vertical
                ? (bar.screen ? bar.screen.height : bar.height)
                : Theme.barHeight + Theme.shadowPad,
            barThickness: Theme.barHeight,
            shadowPad: Theme.shadowPad,
            hotEdge: Theme.barHotEdge
        })
        x: rect.x
        y: rect.y
        width: rect.width
        height: rect.height
    }

    // El puntero al filo devuelve la barra y la mantiene mientras esté
    // encima o haya un menú abierto, como el dock.
    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hideGrace.stop();
                bar.pointerLeft = false;
                bar.pointerOnBar = true;
            } else {
                bar.pointerLeft = true;
                if (!bar.menuOpen)
                    hideGrace.restart();
            }
        }
    }

    // Margen antes de volver a apartarla: si el ratón va hacia ella, no
    // debe esconderse por el camino.
    Timer {
        id: hideGrace
        interval: Theme.barHideGrace
        onTriggered: if (!bar.menuOpen && bar.pointerLeft)
            bar.pointerOnBar = false
    }

    onMenuOpenChanged: if (!menuOpen && pointerLeft)
        hideGrace.restart()

    // Efecto de entrada: "nace del borde". La barra se destapa desde el filo
    // de la pantalla hacia dentro (crece desde el borde) con un leve fundido.
    // En modo dinámico `reveal` vuelve a 0 cuando el puntero no está
    // encima: la barra se retira hacia el filo (el frame encoge y recorta).
    property real reveal: 0
    Component.onCompleted: reveal = bar.wantsReveal ? 1 : 0
    onWantsRevealChanged: reveal = bar.wantsReveal ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: bar.wantsReveal ? 460 : 220
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: frame
        // Horizontal: ocupa el ancho y crece en alto desde el filo. Vertical:
        // ocupa todo el alto y crece en ancho desde el filo lateral.
        x: bar.vertical ? (bar.atLeft ? 0 : parent.width - width) : 0
        y: bar.vertical ? 0 : (bar.atBottom ? parent.height - height : 0)
        width: bar.vertical
            ? bar.reveal * (Theme.barHeight + Theme.shadowPad)
            : parent.width
        height: bar.vertical
            ? parent.height
            : bar.reveal * (Theme.barHeight + Theme.shadowPad)
        clip: true
        opacity: 0.25 + 0.75 * bar.reveal
        // Centro de la barra visible. El frame incluye el aire de la sombra,
        // así que centrar los módulos en él los deja pegados al borde
        // interior en vez de en el centro de la barra.
        readonly property real barCenterX: bar.vertical
            ? (bar.atLeft
                ? Theme.barHeight / 2
                : parent.width - Theme.barHeight / 2)
            : parent.width / 2
        // Ancla en el centro de la barra: los anchors necesitan una línea de
        // anclaje, no un número.
        Item {
            id: barCenter
            x: frame.barCenterX
            width: 0
            height: 0
        }

        // Mismo problema en el eje vertical de la barra horizontal: el frame
        // mide barHeight + shadowPad, así que su centro queda 6 px del lado
        // interior. El centro real es el de la franja visible.
        readonly property real barCenterY: bar.vertical
            ? parent.height / 2
            : (bar.atBottom
                ? Theme.shadowPad + Theme.barHeight / 2
                : Theme.barHeight / 2)
        Item {
            id: barCenterV
            y: frame.barCenterY
            width: 0
            height: 0
        }

        // Silueta de la barra: se declara una vez y la usan la sombra y la
        // superficie, así que las dos dibujan exactamente la misma forma.
        component GlassPath: ShapePath {
            readonly property int rt: Theme.radiusTop
            readonly property int rb: Theme.radius
            // Largo a lo largo del filo y grosor hacia dentro. Los da la
            // instancia: dentro del componente `parent` no resuelve al Shape.
            required property real len
            required property real thick

            // El trazado se dibuja siempre con el filo arriba (y = 0) y
            // el labio cóncavo. Llevarlo a cada borde es mapear los
            // puntos: abajo e izquierda son espejos (invierten el sentido
            // de los arcos); derecha es un giro que lo conserva.
            function px(x, y) {
                if (bar.atLeft)
                    return y;
                if (bar.atRight)
                    return thick - y;
                return x;
            }
            function py(x, y) {
                if (bar.atLeft || bar.atRight)
                    return x;
                if (bar.atBottom)
                    return thick - y;
                return y;
            }
            function inverse(value) {
                if (!bar.atLeft && !bar.atBottom)
                    return value;
                return value === PathArc.Clockwise
                    ? PathArc.Counterclockwise : PathArc.Clockwise;
            }

            startX: px(0, 0)
            startY: py(0, 0)

            // borde pegado al filo de la pantalla
            PathLine {
                x: px(len, 0)
                y: py(len, 0)
            }

            // primera esquina del filo: se vacía hacia dentro
            PathArc {
                x: px(len - rt, rt)
                y: py(len - rt, rt)
                radiusX: rt
                radiusY: rt
                direction: inverse(PathArc.Counterclockwise)
                useLargeArc: false
            }

            // lado opuesto al filo (derecho)
            PathLine {
                x: px(len - rt, thick - rb)
                y: py(len - rt, thick - rb)
            }

            // esquina opuesta al filo: convexa
            PathArc {
                x: px(len - rt - rb, thick)
                y: py(len - rt - rb, thick)
                radiusX: rb
                radiusY: rb
                direction: inverse(PathArc.Clockwise)
                useLargeArc: false
            }

            // borde opuesto a la pantalla
            PathLine {
                x: px(rt + rb, thick)
                y: py(rt + rb, thick)
            }

            // segunda esquina convexa
            PathArc {
                x: px(rt, thick - rb)
                y: py(rt, thick - rb)
                radiusX: rb
                radiusY: rb
                direction: inverse(PathArc.Clockwise)
                useLargeArc: false
            }

            // lado opuesto al filo (izquierdo)
            PathLine {
                x: px(rt, rt)
                y: py(rt, rt)
            }

            // segunda esquina del filo: se vacía hacia dentro
            PathArc {
                x: px(0, 0)
                y: py(0, 0)
                radiusX: rt
                radiusY: rt
                direction: inverse(PathArc.Counterclockwise)
                useLargeArc: false
            }
        }

        // Sombra de elevación: la misma configuración que usa el dock
        // (blurMax 32 y el desenfoque activo). Con el desenfoque apagado el
        // efecto dejaba su búfer de textura sin inicializar y al
        // reposicionar la barra aparecían bandas de color al final.
        MultiEffect {
            id: elevation
            source: glass
            x: glass.x
            y: glass.y
            width: glass.width
            height: glass.height

            blurMax: 32
            shadowEnabled: true
            shadowColor: Theme.shadowColor
            shadowOpacity: Theme.shadowOpacity
            shadowBlur: Theme.shadowBlur
            // La sombra cae hacia dentro de la pantalla: hacia abajo cuando
            // la barra está arriba, hacia arriba cuando está abajo y hacia el
            // interior cuando está en un lateral.
            shadowHorizontalOffset: bar.atLeft
                ? Theme.shadowOffsetY
                : (bar.atRight ? -Theme.shadowOffsetY : 0)
            shadowVerticalOffset: bar.vertical
                ? 0
                : (bar.atBottom ? -Theme.shadowOffsetY : Theme.shadowOffsetY)
        }

        Shape {
            id: glass
            // Geometría del trazado: largo a lo largo del filo y grosor
            // hacia dentro.
            readonly property real pathLen: bar.vertical ? height : width
            readonly property real pathThick: bar.vertical ? width : height
            antialiasing: true   // suaviza el contorno de las curvas y el borde
            preferredRendererType: Shape.CurveRenderer   // curvas con AA de alta calidad
            // Horizontal: ocupa el ancho y deja el aire de la sombra a los
            // lados. Vertical: ocupa el alto completo y deja ese aire hacia
            // dentro de la pantalla.
            x: bar.vertical ? (bar.atLeft ? 0 : parent.width - width) : Theme.shadowPad
            y: bar.vertical ? 0 : (bar.atBottom ? parent.height - height : 0)
            width: bar.vertical ? Theme.barHeight : parent.width - 2 * Theme.shadowPad
            height: bar.vertical ? parent.height : Theme.barHeight

            // Sin borde: la silueta la define el contraste de la
            // superficie contra el fondo (estilo Material 3).
            GlassPath {
                len: glass.pathLen
                thick: glass.pathThick
                strokeWidth: 0
                strokeColor: "transparent"
                // Superficie Material 3 sólida (token surfaceContainer).
                fillColor: Theme.surface
            }
        }

            // ── Izquierda: escritorios + ventana activa ────────────────
            // Módulos independientes: el selector queda anclado a la
            // izquierda y la ventana activa crece hacia la derecha sin
            // desplazarlo.
            LauncherButton {
                id: launcher
                visible: !bar.vertical
                anchors {
                left: parent.left; leftMargin: bar.edgeMargin
                verticalCenter: barCenterV.verticalCenter
            }
                onActivated: bar.openAppMenu()
            }

            Workspaces {
                id: workspaces
                visible: !bar.vertical
                vertical: bar.vertical
                screenName: bar.screen ? bar.screen.name : ""
                service: bar.workspacesService
                anchors {
                    left: launcher.right; leftMargin: 14
                    verticalCenter: barCenterV.verticalCenter
                }
            }

            ActiveWindow {
                visible: !bar.vertical && appId !== ""
                vertical: bar.vertical
                anchors {
                    left: workspaces.right; leftMargin: 20
                    verticalCenter: barCenterV.verticalCenter
                }
                appId: bar.activeWindowAppId
                compact: bar.compactBar
            }

            // ── Centro: actualización + reloj + notificación activa ──
            // El grupo completo se centra. Al entrar una actualización o
            // una notificación, el reloj corre y el chip aparece a su lado.
            Row {
                id: centerCluster
                visible: !bar.vertical
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: barCenterV.verticalCenter
                }
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

                visible: !bar.vertical && opacity > 0
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
                    verticalCenter: barCenterV.verticalCenter
                }
                cpu: bar.cpuUsage
                ram: bar.ramUsage
                gpu: bar.gpuUsage
                swap: bar.swapUsage
                network: bar.networkUsage
                temperature: bar.resources ? bar.resources.temperature : 0
                resources: bar.resources
                tipAbove: bar.atBottom
                onActivated: bar.openSecondMenu("sistema")
            }

            Row {
                id: rightCluster
                visible: !bar.vertical
                anchors {
                    right: parent.right; rightMargin: bar.edgeMargin
                    verticalCenter: barCenterV.verticalCenter
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

            // ── Barra vertical: tres grupos apilados ──────────────────
            // Arriba selector + escritorios + ventana activa; al centro
            // actualización + reloj + aviso + medio; al pie recursos,
            // bandeja e iconos de estado. Sólo existe en los laterales.
            // Los tres grupos usan ColumnLayout y no Column: con una
            // Column, el ancho del grupo lo definía el hijo más ancho, así
            // que al desplegarse la bandeja el grupo se re-anchuraba y sus
            // hijos, alineados al borde izquierdo, se iban de lado. Aquí el
            // ancho es fijo y cada hijo se centra en la barra.
            ColumnLayout {
                id: verticalTop
                visible: bar.vertical
                width: Theme.barHeight
                anchors {
                    top: parent.top; topMargin: Theme.padH + Theme.radiusTop
                    horizontalCenter: barCenter.horizontalCenter
                }
                spacing: 14

                LauncherButton {
                    id: launcherV
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    onActivated: bar.openAppMenu()
                }

                Workspaces {
                    id: workspacesV
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    vertical: true
                    screenName: bar.screen ? bar.screen.name : ""
                    service: bar.workspacesService
                }

                ActiveWindow {
                    id: activeWindowV
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    vertical: true
                    appId: bar.activeWindowAppId
                    compact: bar.compactBar
                }
            }

            ColumnLayout {
                id: verticalCenter
                visible: bar.vertical
                width: Theme.barHeight
                anchors {
                    horizontalCenter: barCenter.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                UpdateChip {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    vertical: true
                    onActivated: bar.openSecondMenu("configs")
                }
                Clock {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    vertical: true
                    compact: bar.compactBar
                    onActivated: bar.openSecondMenu()
                }
                NotificationChip {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    server: bar.notificationServer
                    vertical: true
                }
                MediaChip {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    vertical: true
                }
            }

            // El pie de la barra vertical se ancla por dentro en vez de
            // fluir en una columna: los iconos de sistema quedan pegados al
            // borde inferior, la bandeja crece hacia arriba desde encima de
            // ellos y los anillos se apoyan sobre la bandeja. Así, al
            // plegar, el borde inferior de la bandeja no se mueve y el
            // grupo no se recompone: nada se va de lado.
            ColumnLayout {
                id: verticalStatusIcons
                visible: bar.vertical
                width: Theme.barHeight
                anchors {
                    bottom: parent.bottom; bottomMargin: Theme.padH + Theme.radiusTop
                    horizontalCenter: barCenter.horizontalCenter
                }
                spacing: 4

                Network {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                }
                PowerProfile {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    profile: bar.powerProfile
                }
                BluetoothIndicator {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                }
                MicVolume {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                }
                Volume {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                }
                PowerButton {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignHCenter
                    onActivated: bar.openPowerMenu()
                }
            }

            Tray {
                id: trayV
                shown: bar.vertical
                vertical: true
                barAtLeft: bar.atLeft
                trayMenuState: bar.trayMenuState
                menusAbove: true
                anchors {
                    bottom: verticalStatusIcons.top; bottomMargin: 16
                    horizontalCenter: barCenter.horizontalCenter
                }
            }

            ResourceMonitor {
                id: resourceMonitorV
                visible: bar.vertical && opacity > 0
                vertical: true
                barAtLeft: bar.atLeft
                cpu: bar.cpuUsage
                ram: bar.ramUsage
                gpu: bar.gpuUsage
                swap: bar.swapUsage
                network: bar.networkUsage
                temperature: bar.resources ? bar.resources.temperature : 0
                resources: bar.resources
                tipAbove: false
                // En vertical la bandeja desplegada crece bajo los anillos y
                // los empujaría fuera de la barra: se apartan mientras esté
                // abierta.
                readonly property bool ringsShown: trayV.collapsed
                opacity: ringsShown ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.durFast + 60
                        easing.type: Easing.OutCubic
                    }
                }
                onActivated: bar.openSecondMenu("sistema")
                anchors {
                    bottom: trayV.top; bottomMargin: 16
                    horizontalCenter: barCenter.horizontalCenter
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
        width: bar.vertical
            ? hitArea.width
            : Math.max(0, bar.activeTray.mapToItem(hitArea, 0, 0).x)
        height: bar.vertical
            ? Math.max(0, bar.activeTray.mapToItem(hitArea, 0, 0).y)
            : hitArea.height
        z: 100
        enabled: bar.trayMenuState !== null && bar.trayMenuState.active !== null
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: bar.closeTrayMenu()
    }

    MouseArea {
        x: bar.vertical
            ? hitArea.x
            : hitArea.x + bar.activeTray.mapToItem(hitArea, 0, 0).x
                + bar.activeTray.width
        y: bar.vertical
            ? hitArea.y + bar.activeTray.mapToItem(hitArea, 0, 0).y
                + bar.activeTray.height
            : hitArea.y
        width: bar.vertical
            ? hitArea.width
            : Math.max(0, hitArea.width
                - bar.activeTray.mapToItem(hitArea, 0, 0).x
                - bar.activeTray.width)
        height: bar.vertical
            ? Math.max(0, hitArea.height
                - bar.activeTray.mapToItem(hitArea, 0, 0).y
                - bar.activeTray.height)
            : hitArea.height
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
                    x: hitArea.x + bar.activeTray.mapToItem(hitArea, 0, 0).x
                    y: bar.vertical
                        ? hitArea.y + bar.activeTray.mapToItem(hitArea, 0, 0).y
                        : (bar.atBottom
                            ? (bar.screen ? bar.screen.height : bar.height) - Theme.barHeight
                            : 0)
                    width: bar.activeTray.width
                    height: bar.vertical ? bar.activeTray.height : Theme.barHeight
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
            menuScreen: bar.modelData
            menuState: bar.powerMenuState
        }
    }

    Loader {
        active: true
        sourceComponent: AppMenu {
            screen: bar.screen
            menuScreen: bar.modelData
            menuState: bar.appMenuState
            clipboardHistory: bar.clipboardHistory
        }
    }

    Loader {
        active: true
        sourceComponent: SecondMenu {
            screen: bar.screen
            menuScreen: bar.modelData
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

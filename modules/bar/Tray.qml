import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../../components"
import "../../theme"
import "../icons"

// Bandeja del sistema (StatusNotifier). Consume los items que ya
// publica el watcher de la sesión (kded6 en Plasma 6).
Item {
    id: root

    property var trayMenuState: null

    // Plegada o desplegada. El estado se recuerda en
    // ~/.config/caparazon/tray.json, así que sobrevive al reinicio.
    property bool collapsed: false
    // Barra abajo: los menús de bandeja tienen que abrir hacia arriba.
    property bool menusAbove: false
    // Barra vertical: la cápsula se apila en columna y crece hacia arriba.
    property bool vertical: false
    // Barra pegada al borde izquierdo: los menús salen hacia la derecha.
    property bool barAtLeft: false
    property bool syncing: false

    readonly property string configDir: Quickshell.env("HOME") + "/.config/caparazon"
    readonly property string configPath: root.configDir + "/tray.json"

    function setCollapsed(value) {
        if (root.collapsed === value)
            return;
        root.collapsed = value;
    }

    function save() {
        writer.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"",
            "bash",
            "{\"collapsed\":" + (root.collapsed ? "true" : "false") + "}",
            root.configPath
        ];
        writer.running = true;
    }

    onCollapsedChanged: if (!root.syncing) root.save()

    Process {
        id: ensureFile
        running: true
        command: [
            "bash", "-c",
            "mkdir -p \"$1\"; [ -f \"$2\" ] || printf '%s\\n' '{\"collapsed\":false}' > \"$2\"",
            "bash",
            root.configDir,
            root.configPath
        ]
        onExited: file.reload()
    }

    Process {
        id: writer
    }

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool collapsed: false
        }
    }

    Connections {
        target: file
        function onLoaded() {
            // Si cambia desde otra barra, se aplica sin reescribir.
            root.syncing = true;
            root.collapsed = adapter.collapsed === true;
            root.syncing = false;
        }
    }

    // Cápsula común para toda la bandeja. Usa el mismo acento que los
    // medidores de audio, con baja opacidad para no competir con los iconos.
    readonly property int capsulePad: 6
    readonly property int capsuleHeight: 32
    readonly property color capsuleColor: Qt.rgba(
        Theme.m3Primary.r, Theme.m3Primary.g, Theme.m3Primary.b, 0.16)

    // Plegado: la cápsula se encoge, recorta a los iconos y éstos se funden
    // escalonados empezando por el borde de la flecha. `open` va de 1
    // (desplegada) a 0 (plegada) con la misma curva que el ancho.
    readonly property int foldDuration: 260
    property real open: root.collapsed ? 0 : 1

    Behavior on open {
        NumberAnimation {
            duration: root.foldDuration
            easing.type: Easing.OutCubic
        }
    }

    // Algunos AppIndicator de Flatpak publican el IconName como una ruta
    // absoluta (/usr/share/icons/...). Esa ruta no existe fuera del sandbox;
    // se usa el nombre del icono para que lo resuelva el tema del host.
    function normalizeIcon(source) {
        const prefix = "image://icon/";
        if (!source || source.indexOf(prefix) !== 0)
            return source;
        let rest = source.substring(prefix.length);
        let query = "";
        const q = rest.indexOf("?");
        if (q >= 0) {
            query = rest.substring(q);
            rest = rest.substring(0, q);
        }
        let decoded = rest;
        try {
            decoded = decodeURIComponent(rest);
        } catch (e) {
            return source;
        }
        if (decoded.charAt(0) !== "/")
            return source;
        let name = decoded.split("/").pop();
        name = name.replace(/\.(png|svg|webp)$/i, "");
        name = name.replace(/\.tray-(idle|recording|paused)$/i, "");
        return prefix + name + query;
    }

    // Plegada ocupa lo mismo que un círculo de estado; desplegada, la
    // cápsula de siempre. El ancho se anima para que el resto de la barra
    // acompañe en vez de saltar.
    implicitWidth: root.width
    implicitHeight: 26
    // En vertical el ancho no cambia al desplegarse: la celda crece en alto
    // y hacia arriba desde el borde inferior, donde viven los botones de
    // sistema. Así el borde de abajo nunca se mueve. Si el ancho variase,
    // el grupo de la barra se re-anchuraba y la bandeja y los botones de
    // sistema se iban de lado.
    width: root.vertical
        ? 26
        : (root.collapsed ? 26 : trayRow.implicitWidth + capsulePad * 2)
    // En vertical el alto es explícito y animado: la bandeja se abre hacia
    // arriba y los anillos que se apoyan en ella la acompañan en el mismo
    // plazo, sin saltos.
    height: root.vertical
        ? (root.collapsed ? 26 : trayRow.implicitHeight + capsulePad * 2)
        : 26
    // `shown` lo usa la barra para montar la bandeja solo en la vertical;
    // el conteo de items manda igualmente.
    property bool shown: true
    visible: root.shown && rep.count > 0

    Behavior on width {
        NumberAnimation {
            duration: root.foldDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on height {
        enabled: root.vertical
        NumberAnimation {
            duration: root.foldDuration
            easing.type: Easing.OutCubic
        }
    }

    // El contenido vive dentro de la cápsula para que el recorte acompañe
    // al encogimiento: los iconos se meten detrás del borde redondeado.
    Rectangle {
        id: capsule
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.right: root.vertical ? undefined : parent.right
        anchors.bottom: parent.bottom
        width: root.vertical ? 26 : root.width
        // En vertical la cápsula llena la celda y se ancla al borde
        // inferior: al plegarse se encoge hacia arriba y su base no se
        // mueve. Ahí el alto ya lo anima el contenedor.
        height: root.vertical
            ? root.height
            : (root.collapsed ? 26 : root.capsuleHeight)
        radius: Math.min(width, height) / 2
        clip: true
        // Plegada usa el acento de los círculos de estado; desplegada,
        // el tinte translúcido de la cápsula.
        color: root.collapsed
            ? (toggleHover.hovered
                ? Qt.lighter(Theme.m3Primary, 1.08)
                : Theme.m3Primary)
            : Qt.rgba(Theme.m3Primary.r, Theme.m3Primary.g,
                Theme.m3Primary.b, toggleHover.hovered ? 0.22 : 0.16)

        Behavior on height {
            enabled: !root.vertical
            NumberAnimation {
                duration: Theme.durFast
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: root.foldDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    Grid {
        id: trayRow
        // Una fila en horizontal; una columna en vertical.
        columns: root.vertical ? 1 : Math.max(1, rep.count + 1)
        flow: Grid.LeftToRight
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.right: root.vertical ? undefined : parent.right
        anchors.rightMargin: root.capsulePad * root.open
        anchors.bottom: root.vertical ? parent.bottom : undefined
        anchors.bottomMargin: root.vertical ? root.capsulePad * root.open : 0
        columnSpacing: 2
        rowSpacing: 2

        Repeater {
            id: rep
            model: SystemTray.items

        delegate: HoverChip {
            id: item
            required property var modelData
            required property int index

            implicitWidth: 26
            implicitHeight: 26
            // Siguen reservando su sitio para que la fila no salte; se
            // funden y encogen, de derecha a izquierda. Al terminar el
            // fundido desaparecen del todo (visible false): la fila deja de
            // desbordarse sobre los anillos y robarles el hover.
            enabled: !root.collapsed
            visible: !root.collapsed || opacity > 0.01
            opacity: root.collapsed ? 0 : 1
            scale: root.collapsed ? 0.7 : 1

            Behavior on opacity {
                NumberAnimation {
                    // Sin `delay` en Qt Quick: el escalón va en la
                    // duración, así el último icono de la fila se va antes.
                    duration: root.foldDuration - 140
                        + (rep.count - 1 - index) * 22
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    // Sin `delay` en Qt Quick: el escalón va en la
                    // duración, así el último icono de la fila se va antes.
                    duration: root.foldDuration - 140
                        + (rep.count - 1 - index) * 22
                    easing.type: Easing.OutCubic
                }
            }
            // La cápsula ya es el fondo del grupo; el hover no debe pintar
            // otro bloque encima del icono seleccionado.
            color: "transparent"

            // SystemTrayItem.icon ya es una URL usable por Image
            // (image://qspixmap/... para pixmaps, image://icon/... para temas).
            IconImage {
                id: trayIcon
                anchors.centerIn: parent
                implicitSize: 16
                transformOrigin: Item.Center
                source: root.normalizeIcon(item.modelData.icon)
                scale: trayHover.hovered ? 1.08 : 1.0

                Behavior on scale {
                    NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: Theme.iconTintMuted
                }
            }

            SequentialAnimation {
                id: trayWobble
                loops: 1

                NumberAnimation {
                    target: trayIcon
                    property: "rotation"
                    to: 12
                    duration: 90
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: trayIcon
                    property: "rotation"
                    to: -9
                    duration: 95
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: trayIcon
                    property: "rotation"
                    to: 6
                    duration: 85
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: trayIcon
                    property: "rotation"
                    to: -3
                    duration: 75
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: trayIcon
                    property: "rotation"
                    to: 0
                    duration: 85
                    easing.type: Easing.OutCubic
                }
                PauseAnimation { duration: 240 }
            }

            NumberAnimation {
                id: trayResetTilt
                target: trayIcon
                property: "rotation"
                to: 0
                duration: 120
                easing.type: Easing.OutCubic
            }

            // Mismo retardo que el tooltip de recursos. El cierre espera un
            // poco para que el puntero pueda pasar del icono a la burbuja.
            Timer {
                id: hoverOpenTimer
                interval: 350
                repeat: false
                onTriggered: {
                    if (root.collapsed || !trayHover.hovered
                            || !item.modelData || !item.modelData.hasMenu)
                        return;
                    const active = root.trayMenuState
                        ? root.trayMenuState.active
                        : null;
                    if (active && active !== trayMenu
                            && typeof active.close === "function")
                        active.close();
                    if (!trayMenu.opened)
                        trayMenu.open();
                }
            }

            Timer {
                id: hoverCloseTimer
                interval: 250
                repeat: false
                onTriggered: {
                    if (trayHover.hovered || trayMenu.menuHovered
                            || submenu.menuHovered)
                        return;
                    if (trayMenu.opened)
                        trayMenu.close();
                }
            }

            HoverHandler {
                id: trayHover

                onHoveredChanged: {
                    if (hovered) {
                        hoverCloseTimer.stop();
                        trayResetTilt.stop();
                        trayWobble.restart();
                        if (item.modelData && item.modelData.hasMenu)
                            hoverOpenTimer.restart();
                    } else {
                        hoverOpenTimer.stop();
                        trayWobble.stop();
                        trayResetTilt.start();
                        if (trayMenu.opened)
                            hoverCloseTimer.restart();
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                property bool menuWasOpenOnPress: false

                onPressed: menuWasOpenOnPress = trayMenu.opened

                function toggleMenu() {
                    if (trayMenu.opened)
                        trayMenu.close();
                    else
                        trayMenu.open();
                }

                onClicked: function (mouse) {
                    if (root.collapsed)
                        return;

                    const tray = item.modelData;

                    // Si el menú ya estaba abierto al pulsar, este clic debe
                    // cerrarlo, no reabrirlo. Especialmente cuando el popup
                    // perdió el foco al pulsar y ya se cerró solo.
                    if (menuWasOpenOnPress) {
                        menuWasOpenOnPress = false;
                        if (trayMenu.opened)
                            trayMenu.close();
                        return;
                    }

                    if (mouse.button === Qt.MiddleButton) {
                        tray.secondaryActivate();
                        return;
                    }
                    if (mouse.button === Qt.LeftButton && !tray.onlyMenu) {
                        tray.activate();
                        return;
                    }
                    if (tray.hasMenu) {
                        toggleMenu();
                        return;
                    }
                    tray.secondaryActivate();
                }

                onWheel: function (wheel) {
                    item.modelData.scroll(wheel.angleDelta.y, false);
                }
            }

            TrayMenu {
                id: trayMenu
                menuHandle: item.modelData.menu
                anchorItem: item
                menuState: root.trayMenuState
                menusAbove: root.menusAbove
                vertical: root.vertical
                barAtLeft: root.barAtLeft
                anchorEdge: root.menusAbove ? Edges.Bottom : Edges.Top
                anchorGravity: root.menusAbove ? Edges.Top : Edges.Bottom

                onSubmenuRequested: function (handle, anchor) {
                    if (!handle)
                        return;
                    // El hover puede pedir el mismo submenú varias veces al
                    // entrar/salir de la fila. No volver a abrirlo ni a
                    // pedir layout otra vez: eso provocaba el parpadeo y
                    // la carga lenta ocasional.
                    if (submenu.opened) {
                        if (submenu.menuHandle === handle)
                            return;
                        // Otro submenú distinto: cerrar antes de cambiar el
                        // handle evita que QsMenuOpener se quede con el
                        // layout anterior mientras el popup sigue visible.
                        submenu.close();
                    }
                    submenu.menuHandle = handle;
                    submenu.anchorItem = anchor;
                    trayMenu.openChild(submenu);
                    // openChild() ya manda sendOpened(). Quickshell 0.3.2
                    // no carga los hijos de un DBusMenuItem al abrir un
                    // QsMenuOpener; forzamos el layout una vez y otra en el
                    // siguiente ciclo para cuando el backend responde tarde.
                    if (typeof handle.updateLayout === "function") {
                        handle.updateLayout();
                        Qt.callLater(function () {
                            if (submenu.opened && submenu.menuHandle === handle)
                                handle.updateLayout();
                        });
                    }
                }
            }

            // Un nivel de submenú (suficiente para Steam: Juegos → juego).
            // Se abre a la izquierda porque la bandeja vive a la derecha.
            TrayMenu {
                id: submenu
                menuHandle: null
                anchorItem: item
                parentMenu: trayMenu
                centerAnchor: false
                grabFocus: false
                vertical: root.vertical
                barAtLeft: root.barAtLeft
                // Se abre a la izquierda y alineado con la fila que lo invoca.
                anchorEdge: Edges.Left | Edges.Top
                anchorGravity: Edges.Left | Edges.Bottom
                anchorAdjustment: PopupAdjustment.SlideY

                onActivated: trayMenu.close()
            }

            Connections {
                target: trayMenu
                function onMenuHoveredChanged() {
                    if (trayMenu.menuHovered) {
                        hoverCloseTimer.stop();
                    } else if (!trayHover.hovered) {
                        hoverCloseTimer.restart();
                    }
                }
            }

            Connections {
                target: submenu
                function onMenuHoveredChanged() {
                    if (submenu.menuHovered) {
                        hoverCloseTimer.stop();
                    } else if (!trayHover.hovered && !trayMenu.menuHovered) {
                        hoverCloseTimer.restart();
                    }
                }
            }
        }
    }

        // Plegar/desplegar la bandeja. Vive en el borde derecho de la
        // cápsula: al plegarla, los iconos se van hacia la izquierda.
        HoverChip {
            id: toggle

            implicitWidth: root.collapsed ? 26 : 22
            implicitHeight: 26
            color: "transparent"
            HoverHandler {
                id: toggleHover
                cursorShape: Qt.PointingHandCursor
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setCollapsed(!root.collapsed)
            }
        }

    }

    // Chevron dibujado en vez del icono del tema: el glifo traía aire
    // asimétrico y al girarlo el trazo quedaba 2 px fuera del centro del
    // círculo. Va anclado a la cápsula (el propio círculo) y el trazo se
    // dibuja alrededor de su centro exacto.
    Shape {
        id: chevron
        readonly property real thickness: 1.8
        readonly property real halfWidth: (root.collapsed ? 5 : 4.5) / 2
        readonly property real halfHeight: (root.collapsed ? 9 : 8) / 2
        readonly property real centerX: width / 2
        readonly property real centerY: height / 2
        width: 26
        height: 26
        anchors.right: root.vertical ? undefined : capsule.right
        anchors.verticalCenter: root.vertical ? undefined : capsule.verticalCenter
        anchors.bottom: root.vertical ? capsule.bottom : undefined
        anchors.horizontalCenter: root.vertical ? capsule.horizontalCenter : undefined
        preferredRendererType: Shape.CurveRenderer
        rotation: root.vertical
            ? (root.collapsed ? -90 : 90)
            : (root.collapsed ? 180 : 0)
        transformOrigin: Item.Center

        Behavior on rotation {
            NumberAnimation {
                duration: root.foldDuration - 80
                easing.type: Easing.OutCubic
            }
        }

        ShapePath {
            strokeWidth: chevron.thickness
            strokeColor: root.collapsed
                ? Theme.m3OnPrimary
                : Theme.iconTintMuted
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: chevron.centerX - chevron.halfWidth
            startY: chevron.centerY - chevron.halfHeight
            PathLine {
                x: chevron.centerX + chevron.halfWidth
                y: chevron.centerY
            }
            PathLine {
                x: chevron.centerX - chevron.halfWidth
                y: chevron.centerY + chevron.halfHeight
            }
        }
    }
}

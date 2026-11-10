import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
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
    // cápsula de siempre.
    implicitWidth: trayRow.implicitWidth + (root.collapsed ? 0 : capsulePad * 2)
    implicitHeight: 26
    visible: rep.count > 0

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.collapsed ? 26 : root.capsuleHeight
        radius: height / 2
        // Plegada usa el acento de los círculos de estado; desplegada,
        // el tinte translúcido de la cápsula.
        color: root.collapsed
            ? (toggleHover.hovered
                ? Qt.lighter(Theme.m3Primary, 1.08)
                : Theme.m3Primary)
            : Qt.rgba(Theme.m3Primary.r, Theme.m3Primary.g,
                Theme.m3Primary.b, toggleHover.hovered ? 0.22 : 0.16)

        Behavior on height {
            NumberAnimation {
                duration: Theme.durFast
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Theme.durFast
                easing.type: Easing.OutCubic
            }
        }
    }

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            id: rep
            model: SystemTray.items

        delegate: HoverChip {
            id: item
            required property var modelData

            implicitWidth: 26
            implicitHeight: 26
            visible: !root.collapsed
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
                    if (!trayHover.hovered || !item.modelData
                            || !item.modelData.hasMenu)
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
                showArrow: false
                grabFocus: false
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

            IconImage {
                anchors.centerIn: parent
                implicitSize: root.collapsed ? 16 : 14
                source: IconResolver.firstOf([
                    "pan-end-symbolic",
                    "go-next-symbolic"
                ])
                rotation: root.collapsed ? 180 : 0
                transformOrigin: Item.Center

                Behavior on rotation {
                    NumberAnimation {
                        duration: Theme.durFast
                        easing.type: Easing.OutCubic
                    }
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.collapsed
                        ? Theme.m3OnPrimary
                        : Theme.iconTintMuted
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setCollapsed(!root.collapsed)
            }
        }
    }
}

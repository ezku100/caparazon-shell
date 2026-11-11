import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"
import "../appmenu"

// Menú secundario (calendario). Comparte el chrome del menú de apps pero es
// independiente: no tiene buscador y sólo expone la categoría Calendario.
PanelWindow {
    id: root

    required property var menuState
    required property var screen
    property var notificationHistory: null

    // Métricas del monitor del sistema: llegan desde la barra.
    property int cpuUsage: 0
    property int ramUsage: 0
    property int gpuUsage: 0
    property int swapUsage: 0
    property int networkUsage: 0
    property int temperature: 0
    property var metricSamples: []
    property var resources: null

    readonly property bool opened: menuState ? menuState.opened : false
    readonly property bool active: opened && menuState.activeScreen === screen
    property bool closing: false
    property bool overlayOpen: false

    readonly property int animDuration: 220
    // Lenguaje unificado de apertura/cierre (ver tests/test_menus_animacion.py).
    readonly property int animOpen: 260
    readonly property int animClose: 170
    readonly property int cardWidth: Math.min(760,
        Math.max(600, Math.round((screen ? screen.width : 1920) * 0.52)))
    readonly property int cardHeight: Math.min(500,
        Math.max(400, Math.round((screen ? screen.height : 1080) * 0.68)))
    readonly property int railWidth: 60
    readonly property int railInset: 8
    readonly property string category: menuState ? menuState.category : "calendario"

    readonly property var categories: [
        { key: "calendario", icon: "notifications", label: "Calendario" },
        { key: "musica", icon: "audio", label: "Música" },
        { key: "sistema", icon: "utilities-system-monitor", label: "Monitor del sistema" },
        { key: "configs", glyph: "猫", label: "Configs de Caparazón Shell" }
    ]

    function close() {
        if (root.menuState)
            root.menuState.close();
    }

    readonly property string openAppScript: String(Qt.resolvedUrl("openapp.sh"))
        .replace(/^file:\/\//, "")

    function openNotificationApp(entry) {
        if (!entry || entry.length === 0)
            return;
        openAppProc.command = ["bash", root.openAppScript, entry];
        openAppProc.running = true;
        root.close();
    }

    // La ventana queda cacheada (ver Bar.qml): se mapea solo en la pantalla
    // que abrio el menu y durante su despedida.
    visible: (root.opened || root.closing)
        && root.menuState
        && root.menuState.activeScreen === root.screen
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: root.active
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.active
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    onOpenedChanged: {
        if (root.opened) {
            root.closing = false;
            closeTimer.stop();
            if (root.category === "calendario" && panelLoader.item && typeof panelLoader.item.resetToToday === "function")
                panelLoader.item.resetToToday();
        } else {
            root.closing = true;
            closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer
        interval: root.animClose + 20
        onTriggered: {
            root.closing = false;
            if (root.menuState
                    && typeof root.menuState.finishClose === "function")
                root.menuState.finishClose();
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.active && !root.overlayOpen
        onActivated: root.close()
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "#000000"
        opacity: root.opened ? 0.26 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.opened ? root.animOpen : root.animClose
                easing.type: root.opened ? Easing.OutQuint : Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.close()
    }

    Item {
        id: card
        anchors.centerIn: parent
        width: root.cardWidth
        height: root.cardHeight
        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 0.92
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation {
                duration: root.active ? 200 : root.animClose
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.active ? root.animOpen : root.animClose
                easing.type: root.active ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.2
            }
        }

        transform: Translate {
            y: root.active ? 0 : 14
            Behavior on y {
                NumberAnimation {
                    duration: root.active ? root.animOpen : root.animClose
                    easing.type: root.active ? Easing.OutBack : Easing.InCubic
                    easing.overshoot: 1.2
                }
            }
        }

        Item {
            id: cardBounds
            anchors.fill: parent
        }

        MultiEffect {
            id: cardFx
            source: cardSurface
            anchors.fill: cardSurface
            blurMax: 64
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.38
            shadowBlur: 0.85
            shadowScale: 0.97
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 16
        }

        Rectangle {
            id: cardSurface
            anchors.fill: parent
            radius: 24
            color: Theme.surface
            border.width: 1
            border.color: Theme.m3OutlineVariant
            visible: false
        }

        // Evita que un clic en el fondo de la tarjeta cierre el menú.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        Rectangle {
            id: rail
            x: root.railInset
            y: root.railInset
            width: root.railWidth - 2 * root.railInset
            height: parent.height - 2 * root.railInset
            radius: 18
            color: Theme.chip

            Column {
                anchors {
                    top: parent.top
                    topMargin: 12
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 3

                Repeater {
                    model: root.categories
                    delegate: RailButton {
                        icon: modelData.icon || ""
                        glyph: modelData.glyph || ""
                        selected: root.category === modelData.key
                        onActivated: {
                            if (root.menuState)
                                root.menuState.category = modelData.key;
                        }

                        // Rail en cascada: los botones desfazan 45 ms; al cerrar
                        // el desfase vale cero.
                        opacity: root.active ? 1 : 0
                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation {
                                    duration: root.active ? index * 45 : 0
                                }
                                NumberAnimation {
                                    duration: root.active ? root.animOpen : root.animClose
                                    easing.type: root.active ? Easing.OutQuint : Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: contentArea
            anchors {
                left: rail.right
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                leftMargin: 20 + root.railInset
                rightMargin: 20
                topMargin: 18
                bottomMargin: 18
            }

            Loader {
                id: panelLoader
                anchors.fill: parent
                // El panel acompana la tarjeta: fundido con lift propio;
                // al cambiar de seccion el contenido ya esta asentado.
                opacity: root.active ? 1 : 0
                transform: Translate {
                    y: root.active ? 0 : 16
                    Behavior on y {
                        NumberAnimation {
                            duration: root.active ? root.animOpen : root.animClose
                            easing.type: root.active ? Easing.OutQuint : Easing.OutCubic
                        }
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.active ? root.animOpen : root.animClose
                        easing.type: root.active ? Easing.OutQuint : Easing.OutCubic
                    }
                }
                sourceComponent: {
                    if (root.category === "configs")
                        return configComponent;
                    if (root.category === "musica")
                        return musicComponent;
                    if (root.category === "sistema")
                        return systemComponent;
                    return calendarComponent;
                }
            }

            Component {
                id: calendarComponent
                CalendarPanel {
                    anchors.fill: parent
                    notificationHistory: root.notificationHistory
                    onNotificationActivated: root.openNotificationApp(entry)
                    onOverlayChanged: (open) => root.overlayOpen = open
                }
            }

            Component {
                id: musicComponent
                MusicPanel {
                    anchors.fill: parent
                }
            }

            Component {
                id: systemComponent
                SystemMonitorPanel {
                    anchors.fill: parent
                    cpu: root.cpuUsage
                    ram: root.ramUsage
                    gpu: root.gpuUsage
                    swap: root.swapUsage
                    network: root.networkUsage
                    temperature: root.temperature
                    samples: root.metricSamples
                    resources: root.resources
                }
            }

            Component {
                id: configComponent
                ShellConfigPanel {
                    anchors.fill: parent
                }
            }
        }
    }

    Process {
        id: openAppProc
    }
}

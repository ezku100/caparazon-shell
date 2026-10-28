import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../icons"
import "../icons/BarIcons.js" as BarIcons
import "../../theme"

// Menú de sesión tipo Android: acciones circulares sin tarjeta ni etiquetas.
// La capa oscura cubre todas las pantallas; los botones sólo aparecen en la
// pantalla cuya barra abrió el menú.
PanelWindow {
    id: root

    required property var menuState

    readonly property bool opened: menuState ? menuState.opened : false
    readonly property bool active: opened
        && menuState.activeScreen === screen
    property bool closing: false
    readonly property int animDuration: 260
    readonly property int farewellHold: 900
    readonly property int typeInterval: 70
    readonly property int farewellFontSize: Math.round(Math.min(78, Math.max(44, width * 0.04)))
    property bool farewell: false
    property bool farewellVisible: false
    property string farewellMessage: ""
    property string pendingAction: ""
    property int typedChars: 0
    readonly property string farewellFontFamily: "Noto Serif CJK JP"
    readonly property var farewellMessages: ({
        "lock": "あまり遅くならないで",
        "logout": "またね",
        "shutdown": "またあとでね",
        "reboot": "またすぐ会おう"
    })

    function beginAction(key) {
        if (!active || farewell)
            return;
        const message = farewellMessages[key];
        if (!message)
            return;
        pendingAction = key;
        farewellMessage = message;
        farewell = true;
        farewellVisible = false;
        typedChars = 0;
        typingTimer.stop();
        farewellActionTimer.stop();
        farewellTextTimer.restart();
    }

    function cancelFarewell() {
        farewellTextTimer.stop();
        typingTimer.stop();
        farewellActionTimer.stop();
        farewell = false;
        farewellVisible = false;
        farewellMessage = "";
        pendingAction = "";
        typedChars = 0;
    }

    function executePending() {
        const key = pendingAction;
        pendingAction = "";
        if (key)
            runAction(key);
    }

    Timer {
        id: farewellTextTimer
        interval: root.animDuration
        onTriggered: {
            if (!root.farewell)
                return;
            root.farewellVisible = true;
            root.typedChars = 0;
            typingTimer.restart();
        }
    }

    Timer {
        id: typingTimer
        interval: root.typeInterval
        repeat: true
        onTriggered: {
            if (root.typedChars < root.farewellMessage.length) {
                root.typedChars += 1;
                if (root.typedChars >= root.farewellMessage.length) {
                    stop();
                    farewellActionTimer.start();
                }
            } else {
                stop();
                farewellActionTimer.start();
            }
        }
    }

    Timer {
        id: farewellActionTimer
        interval: root.farewellHold
        onTriggered: root.executePending()
    }

    onOpenedChanged: {
        if (opened) {
            closing = false;
            closeTimer.stop();
            farewellTextTimer.stop();
            typingTimer.stop();
            farewellActionTimer.stop();
            farewell = false;
            farewellVisible = false;
            farewellMessage = "";
            pendingAction = "";
            typedChars = 0;
            scrim.opacity = 0;
            Qt.callLater(function() {
                if (root.opened)
                    scrim.opacity = 0.52;
            });
        } else {
            cancelFarewell();
            scrim.opacity = 0;
            closing = true;
            closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer
        interval: root.animDuration
        onTriggered: {
            root.closing = false;
            if (root.menuState && typeof root.menuState.finishClose === "function")
                root.menuState.finishClose();
        }
    }


    function runAction(key) {
        let command = null;
        if (key === "lock") {
            command = ["loginctl", "lock-session"];
        } else if (key === "logout") {
            command = ["qdbus6", "org.kde.Shutdown", "/Shutdown",
                       "org.kde.Shutdown.logout"];
        } else if (key === "shutdown") {
            command = ["systemctl", "poweroff"];
        } else if (key === "reboot") {
            command = ["systemctl", "reboot"];
        }
        if (!command)
            return;

        menuState.close();
        Qt.callLater(function() { Quickshell.execDetached(command); });
    }

    visible: opened || closing
    anchors { top: true; left: true; right: true; bottom: true }
    // Ignora las zonas exclusivas de barra/dock: así la capa cubre el
    // monitor completo, no sólo el área de trabajo.
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: active
    color: "transparent"
    // Desenfoque del escritorio detrás del scrim (ext-background-effect-v1).
    BackgroundEffect.blurRegion: Region { item: root.contentItem }
    // Por encima de barra, dock y popups.
    WlrLayershell.layer: WlrLayer.Overlay
    // Foco exclusivo para que Escape funcione sin tener que hacer clic dentro.
    WlrLayershell.keyboardFocus: root.active
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    Shortcut {
        sequence: "Escape"
        enabled: root.active
        onActivated: root.menuState.close()
    }

    // Scrim global: oscurece todas las pantallas y captura el clic fuera.
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "#000000"
        opacity: 0
        Behavior on opacity {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.opened
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.menuState.close()
    }

    Item {
        id: content
        anchors.fill: parent
        visible: root.opened || root.closing
        enabled: root.active && !root.farewell
        opacity: root.farewell ? 0 : (root.active ? 1 : 0)
        scale: root.farewell ? 0.92 : (root.active ? 1 : 0.80)
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.animDuration
                easing.type: Easing.OutBack
                easing.overshoot: 1.04
            }
        }

        Row {
            id: actionsRow
            anchors.centerIn: parent
            spacing: 24

            Repeater {
                model: [
                    { key: "lock",     delay: 0 },
                    { key: "logout",   delay: 55 },
                    { key: "shutdown", delay: 110 },
                    { key: "reboot",   delay: 165 }
                ]

                delegate: Item {
                    id: action

                    required property var modelData
                    // Sin circulo de fondo el icono es el unico protagonista:
                    // en reposo se apaga con el mismo tinte que los iconos
                    // inactivos del dock y al pasar el raton se enciende con
                    // el color de superficie, sin invertir tonos.
                    property color iconColor: actionHover.hovered
                        ? Theme.text
                        : Theme.textDim

                    Behavior on iconColor {
                        ColorAnimation {
                            duration: Theme.durFast
                            easing.type: Easing.OutCubic
                        }
                    }

                    width: 128
                    height: 128
                    opacity: root.active ? 1 : 0
                    scale: actionMouse.pressed ? 0.90
                        : actionHover.hovered ? 1.10 : 1
                    transformOrigin: Item.Center

                    transform: Translate {
                        y: (root.active ? 0 : 18)
                            + (actionHover.hovered && !actionMouse.pressed ? -3 : 0)
                        Behavior on y {
                            SpringAnimation {
                                spring: 4.2
                                damping: 0.42
                                mass: 1
                                epsilon: 0.005
                            }
                        }
                    }

                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: action.modelData.delay }
                            NumberAnimation {
                                duration: root.animDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Behavior on scale {
                        SpringAnimation {
                            spring: 4.2
                            damping: 0.42
                            mass: 1
                            epsilon: 0.005
                        }
                    }

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 88
                        source: IconResolver.firstOf(BarIcons.sessionNames(modelData.key))
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: action.iconColor
                        }
                    }

                    HoverHandler {
                        id: actionHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.beginAction(modelData.key)
                    }
                }
            }
        }
    }


    // Fase de despedida: los botones se van y aparece una frase en cursiva
    // con un resplandor suave antes de ejecutar la acción.
    Item {
        id: farewellLayer
        anchors.fill: parent
        visible: root.active
        opacity: root.farewellVisible ? 1 : 0
        scale: root.farewellVisible ? 1 : 0.94
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.03 }
        }

        transform: Translate {
            y: root.farewellVisible ? 0 : 12
            Behavior on y {
                NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
            }
        }

        TextMetrics {
            id: farewellMetrics
            font.family: root.farewellFontFamily
            font.pixelSize: root.farewellFontSize
            text: root.farewellMessage
        }

        Text {
            id: farewellGlow
            x: (parent.width - farewellMetrics.width) / 2
            width: farewellMetrics.width
            anchors.verticalCenter: parent.verticalCenter
            text: farewellText.text
            color: "#FFFFFF"
            font: farewellText.font
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.NoWrap
            opacity: 0.55
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
            }
        }

        Text {
            id: farewellText
            x: (parent.width - farewellMetrics.width) / 2
            width: farewellMetrics.width
            anchors.verticalCenter: parent.verticalCenter
            text: root.farewellMessage.substring(0, root.typedChars)
            color: "#FFFFFF"
            font.family: root.farewellFontFamily
            font.pixelSize: root.farewellFontSize
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.NoWrap
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#CCFFFFFF"
                shadowOpacity: 0.85
                shadowBlur: 0.9
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }
        }
    }
}

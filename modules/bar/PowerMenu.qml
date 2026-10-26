import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
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
                    { key: "lock",     icon: "\u{F033E}", delay: 0 },
                    { key: "logout",   icon: "\u{F0343}", delay: 55 },
                    { key: "shutdown", icon: "\u{F0425}", delay: 110 },
                    { key: "reboot",   icon: "\u{F0709}", delay: 165 }
                ]

                delegate: Item {
                    id: action

                    required property var modelData
                    property real rippleX: width / 2
                    property real rippleY: height / 2

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

                    Rectangle {
                        id: circle
                        anchors.fill: parent
                        radius: width / 2
                        color: actionMouse.pressed
                            ? Qt.darker(Theme.m3Primary, 1.08)
                            : actionHover.hovered
                                ? Theme.m3Primary
                                : Theme.chip
                        border.width: actionHover.hovered || actionMouse.pressed ? 0 : 1
                        border.color: Theme.hairline

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.durFast
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Rectangle {
                        id: ripple
                        x: action.rippleX - width / 2
                        y: action.rippleY - height / 2
                        width: 0
                        height: 0
                        radius: width / 2
                        color: Theme.m3Surface
                        opacity: 0
                    }

                    ParallelAnimation {
                        id: rippleAnim
                        NumberAnimation {
                            target: ripple
                            property: "width"
                            from: 0
                            to: 104
                            duration: 460
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: ripple
                            property: "height"
                            from: 0
                            to: 104
                            duration: 460
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: ripple
                            property: "opacity"
                            from: 0.26
                            to: 0
                            duration: 460
                            easing.type: Easing.OutCubic
                        }
                    }

                    Text {
                        anchors.centerIn: circle
                        text: modelData.icon
                        color: actionHover.hovered
                            ? Theme.m3Surface
                            : Theme.m3Primary
                        font.family: Theme.fontIcon
                        font.pixelSize: 52

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.durFast
                                easing.type: Easing.OutCubic
                            }
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
                        onPressed: function(mouse) {
                            action.rippleX = Math.max(56, Math.min(action.width - 56, mouse.x));
                            action.rippleY = Math.max(56, Math.min(action.height - 56, mouse.y));
                            rippleAnim.restart();
                        }
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

import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"

Item {
    id: root

    property var app: ({})
    property int instanceCount: 0
    property bool focused: false

    signal activated(bool newInstance)
    signal menuRequested(var anchorItem)

    readonly property bool running: root.instanceCount > 0
    readonly property color iconColor: root.running
        ? Theme.m3Primary
        : (hover.hovered ? Theme.text : Theme.textDim)
    readonly property color dotColor: root.focused
        ? Theme.m3Primary
        : Theme.textDim
    readonly property string iconSource: {
        const icon = root.app.icon || "application-x-executable";
        if (icon.indexOf("/") === 0)
            return Qt.resolvedUrl(icon);
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    implicitWidth: 44
    implicitHeight: 44
    IconImage {
        id: appIcon
        anchors.centerIn: parent
        implicitSize: 24
        transformOrigin: Item.Center
        scale: hover.hovered ? 1.07 : 1.0
        transform: Translate {
            y: hover.hovered ? -1 : 0
            Behavior on y {
                NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
            }
        }
        source: root.iconSource

        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.iconColor
            shadowEnabled: hover.hovered || shadowOpacity > 0.01
            shadowColor: Theme.glowColor
            shadowBlur: 0.55
            shadowOpacity: hover.hovered ? 0.80 : 0.0
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0

            Behavior on shadowOpacity {
                NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
            }
        }

        Behavior on scale {
            NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    SequentialAnimation {
        id: hoverWobble
        loops: Animation.Infinite

        NumberAnimation {
            target: appIcon
            property: "rotation"
            to: 12
            duration: 90
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: appIcon
            property: "rotation"
            to: -9
            duration: 95
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: appIcon
            property: "rotation"
            to: 6
            duration: 85
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: appIcon
            property: "rotation"
            to: -3
            duration: 75
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: appIcon
            property: "rotation"
            to: 0
            duration: 85
            easing.type: Easing.OutCubic
        }
        PauseAnimation { duration: 240 }
    }

    NumberAnimation {
        id: resetTilt
        target: appIcon
        property: "rotation"
        to: 0
        duration: 120
        easing.type: Easing.OutCubic
    }

    // Indicador de app abierta: punto inferior, sin cápsula de fondo.
    Rectangle {
        id: runningDot
        visible: root.running
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
        }
        width: 4
        height: 4
        radius: width / 2
        color: root.dotColor
        opacity: root.focused ? 1.0 : 0.65

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        visible: root.instanceCount > 1
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: -3
            topMargin: -3
        }
        width: 17
        height: 17
        radius: width / 2
        color: Theme.m3Primary
        border.width: 2
        border.color: Theme.surface

        Text {
            anchors.centerIn: parent
            text: root.instanceCount > 9 ? "9+" : String(root.instanceCount)
            color: Theme.m3Surface
            font.family: Theme.fontUI
            font.pixelSize: 9
            font.weight: Font.Bold
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.menuRequested(root);
                return;
            }
            root.activated(mouse.button === Qt.MiddleButton);
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor

        onHoveredChanged: {
            if (hovered) {
                resetTilt.stop();
                hoverWobble.restart();
            } else {
                hoverWobble.stop();
                resetTilt.start();
            }
        }
    }
}

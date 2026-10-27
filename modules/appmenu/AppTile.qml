import Quickshell
import Quickshell.Widgets
import QtQuick
import "../../theme"

// Icono de aplicación del menú central. Conserva el icono original para que
// sea reconocible y reutiliza el tambaleo en bucle del dock al pasar el ratón.
Item {
    id: root

    required property var entry
    // Seleccionada por el cursor del menú: el dispositivo que esté mandando
    // (flechas o ratón) decide cuál es.
    property bool selected: false

    // El puntero está sobre la tarjeta. El menú lo necesita para mover el
    // cursor cuando el ratón es el que manda.
    readonly property bool hovered: hover.hovered
    signal hoverEntered()
    signal hoverExited()

    // Fondo, texto y tambaleo siguen al cursor, así que nunca hay dos
    // tarjetas iluminadas a la vez.
    readonly property bool active: root.selected

    onHoveredChanged: {
        if (root.hovered)
            root.hoverEntered();
        else
            root.hoverExited();
    }

    onActiveChanged: {
        if (root.active) {
            resetTilt.stop();
            hoverWobble.restart();
        } else {
            hoverWobble.stop();
            resetTilt.start();
        }
    }

    // Una tarjeta que nace ya seleccionada también debe tambalear.
    Component.onCompleted: {
        if (root.active)
            hoverWobble.restart();
    }

    signal activated()

    readonly property string iconSource: {
        const icon = root.entry && root.entry.icon
            ? String(root.entry.icon)
            : "application-x-executable";
        if (icon.indexOf("/") === 0)
            return Qt.resolvedUrl(icon);
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    implicitWidth: 106
    implicitHeight: 108

    Rectangle {
        id: hoverPill
        anchors.fill: parent
        anchors.margins: 4
        radius: 16
        color: root.active ? Theme.chipHover : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        id: iconBox
        anchors {
            top: parent.top
            topMargin: 12
            horizontalCenter: parent.horizontalCenter
        }
        width: 54
        height: 54
        // Sólo posiciona el icono: el fondo de hover lo pone hoverPill.
        color: "transparent"

        IconImage {
            id: appIcon
            anchors.centerIn: parent
            implicitSize: 42
            source: root.iconSource
            transformOrigin: Item.Center
        }
    }

    Text {
        anchors {
            top: iconBox.bottom
            topMargin: 7
            left: parent.left
            right: parent.right
            leftMargin: 7
            rightMargin: 7
        }
        text: root.entry && root.entry.name ? root.entry.name : ""
        color: root.active ? Theme.text : Theme.textDim
        font.family: Theme.fontUI
        font.pixelSize: 12
        font.weight: Font.Medium
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
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

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

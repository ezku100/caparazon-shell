import QtQuick
import "../theme"

// Chip con hover animado. No consume clics (HoverHandler, no MouseArea),
// así el widget que lo use pone su propio MouseArea encima.
Rectangle {
    id: chip

    implicitWidth: 28
    implicitHeight: 26
    radius: 9
    color: hover.hovered ? Theme.chipHover : "transparent"

    Behavior on color {
        ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
}

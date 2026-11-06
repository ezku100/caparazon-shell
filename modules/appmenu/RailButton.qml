import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"

// Botón de la barra lateral del menú: sólo icono, como el resto del shell.
Item {
    id: root

    property string icon: "application-x-executable"
    property bool selected: false
    // false = se muestra el icono con sus colores originales (logo de la distro)
    property bool tint: true
    // Si no está vacío, pinta un glifo de texto en vez del icono (kanji 猫).
    property string glyph: ""

    signal activated()

    implicitWidth: 36
    implicitHeight: 32

    // La selección y el hover se pintan en dos capas: así el tono cambia de
    // golpe (m3Primary / chipHover) y lo que se anima es la opacidad. Animar
    // el color pasando por "transparent" ennegrecía el fondo a mitad de fundido.
    Rectangle {
        anchors.fill: parent
        radius: 11
        color: Theme.m3Primary
        opacity: root.selected ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: Theme.chipHover
        opacity: !root.selected && hover.hovered ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    IconImage {
        anchors.centerIn: parent
        visible: root.glyph === ""
        implicitSize: 18
        source: IconResolver.source(root.icon, "application-x-executable")
        layer.enabled: root.tint
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: hover.hovered
                ? Theme.text
                : Theme.textDim
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.glyph !== ""
        text: root.glyph
        color: hover.hovered
            ? Theme.text
            : Theme.textDim
        font.family: Theme.fontJP
        font.pixelSize: 17
        font.weight: Font.DemiBold
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}

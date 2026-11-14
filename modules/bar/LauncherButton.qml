import QtQuick
import QtQuick.Effects
import "../../theme"

// Botón de aplicaciones de la barra. Quickshell 0.3 no expone atajos
// globales, así que el menú se abre desde aquí.
Item {
    id: root

    // En la barra vertical el resto de botones lleva un círculo de fondo
    // permanente; el lanzador lleva el kanji limpio.
    signal activated()

    implicitWidth: 28
    implicitHeight: 26

    Rectangle {
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: width / 2
        // Sólo al pasar el puntero: el kanji va sin fondo en ambas barras.
        color: hover.hovered ? Qt.lighter(Theme.chipHover, 1.45) : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    // Kanji de neko (猫) en el color de enfasis. El logo de la distro sólo
    // aparece si el tema de iconos lo trae, así que el botón acababa con un
    // icono genérico que no destacaba en la barra.
    Text {
        anchors.centerIn: parent
        text: "猫"
        color: Theme.m3Primary
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

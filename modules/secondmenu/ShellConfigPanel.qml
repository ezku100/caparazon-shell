import Quickshell
import Quickshell.Io
import QtQuick
import "../../theme"

/*
  Configs de la shell — estilo de color.

  Las tres paletas las genera accent-theme con el acento de KDE: Material usa
  los roles oscuros tal cual, OLED parte de ellos y sube la saturación, y
  Perla usa los roles claros. El panel sólo cambia ThemeStyle; MatugenPalette
  lee la paleta elegida y el resto de la interfaz se repinta sola.

  Si una paleta no está instalada, su fila queda desactivada con un aviso y
  la paleta activa vuelve a Material para no quedarse sin colores.
*/
Item {
    id: root

    readonly property var styleRows: [
        {
            key: "material",
            label: "Material",
            note: "Material 3, sigue al acento de KDE."
        },
        {
            key: "oled",
            label: "OLED",
            note: "Negro puro con acentos más vivos."
        },
        {
            key: "perla",
            label: "Perla",
            note: "Blanco perla con acentos en tono claro."
        }
    ]

    readonly property var availablePalettes: {
        const list = [];
        if (materialFile.loaded)
            list.push("material");
        if (oledFile.loaded)
            list.push("oled");
        if (perlaFile.loaded)
            list.push("perla");
        return list;
    }

    // La fila de cada estilo enseña las muestras de su propia paleta. Se
    // resuelve con una función para que el Repeater no se reconstruya cada
    // vez que cambia el acento.
    function previewFor(key) {
        if (key === "oled")
            return oledAdapter;
        if (key === "perla")
            return perlaAdapter;
        return materialAdapter;
    }

    onAvailablePalettesChanged: {
        if (root.availablePalettes.length === 0)
            return;
        if (root.availablePalettes.indexOf(ThemeStyle.style) === -1)
            ThemeStyle.setStyle("material");
    }

    Column {
        anchors.fill: parent
        spacing: 12

        // Cabecera con la misma altura que la del monitor: el título se
        // centra con anclas y sin altura explícita no se dibujaría.
        Row {
            width: parent.width
            height: 22

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Configs de la shell"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
        }

        Text {
            width: parent.width
            text: "Estilo de color"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.fontPx
        }

        Column {
            width: parent.width
            spacing: 8

            Repeater {
                model: root.styleRows

                delegate: Rectangle {
                    id: row

                    required property var modelData

                    readonly property bool current:
                        ThemeStyle.style === row.modelData.key
                    readonly property bool available:
                        root.availablePalettes.indexOf(row.modelData.key) !== -1

                    width: parent.width
                    height: 64
                    radius: 14
                    color: row.current ? Theme.m3Primary : Theme.chip
                    opacity: row.available ? 1 : 0.55

                    Behavior on color {
                        ColorAnimation { duration: Theme.durFast }
                    }

                    // Muestras: fondo, superficie y acento del estilo.
                    Row {
                        id: swatches
                        anchors {
                            right: parent.right
                            rightMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 4

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 5
                            color: root.previewFor(row.modelData.key).surfaceContainer
                        }

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 5
                            color: root.previewFor(row.modelData.key).surfaceContainerHigh
                        }

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 5
                            color: root.previewFor(row.modelData.key).primary
                        }
                    }

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: 14
                            right: swatches.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Rectangle {
                            width: 12
                            height: 12
                            radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: row.current ? Theme.m3OnPrimary : "transparent"
                            border.width: row.current ? 0 : 1
                            border.color: Theme.m3Outline
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 22
                            spacing: 2

                            Text {
                                width: parent.width
                                text: row.modelData.label
                                color: row.current
                                    ? Theme.m3OnPrimary
                                    : Theme.text
                                font.family: Theme.fontUI
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: row.available
                                    ? row.modelData.note
                                    : "Falta instalar esta paleta"
                                color: row.current
                                    ? Theme.m3OnPrimary
                                    : Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: row.available
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ThemeStyle.setStyle(row.modelData.key)
                    }
                }
            }
        }
    }

    FileView {
        id: materialFile
        path: ThemeStyle.palettePathFor("material")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: materialAdapter
            property string surfaceContainer: "#211f26"
            property string surfaceContainerHigh: "#2b2930"
            property string primary: "#d0bcff"
        }
    }

    FileView {
        id: oledFile
        path: ThemeStyle.palettePathFor("oled")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: oledAdapter
            property string surfaceContainer: "#211f26"
            property string surfaceContainerHigh: "#2b2930"
            property string primary: "#d0bcff"
        }
    }

    FileView {
        id: perlaFile
        path: ThemeStyle.palettePathFor("perla")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: perlaAdapter
            property string surfaceContainer: "#211f26"
            property string surfaceContainerHigh: "#2b2930"
            property string primary: "#d0bcff"
        }
    }
}

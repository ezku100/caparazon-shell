import Quickshell
import Quickshell.Io
import QtQuick
import "../../theme"

/*
  Configs de la shell — estilo de color y modo del dock.

  Las tres paletas las genera accent-theme con el acento de KDE: Material usa
  los roles oscuros tal cual, OLED parte de ellos y sube la saturación, y
  Perla usa los roles claros. El panel sólo cambia ThemeStyle; MatugenPalette
  lee la paleta elegida y el resto de la interfaz se repinta sola.

  El modo del dock (dinámico o anclado) vive en la clave "dockPinned" de
  dock.json, el mismo archivo que lee el dock; se parchea con python3 para
  no reescribir la lista de apps ancladas que también vive ahí.

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

    // Un FileView sin archivo nunca emite loaded: sin el rastro de fallos,
    // una paleta ausente y una que aún carga serían indistinguibles.
    property bool materialFailed: false
    property bool oledFailed: false
    property bool perlaFailed: false

    readonly property bool palettesSettled:
        (materialFile.loaded || root.materialFailed)
            && (oledFile.loaded || root.oledFailed)
            && (perlaFile.loaded || root.perlaFailed)

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

    // El regreso a Material sólo puede decidirse cuando las tres paletas
    // están resueltas: durante la carga una paleta ausente se ve igual que
    // una pendiente y pisaría el estilo guardado al abrir el panel.
    function reconcileActiveStyle() {
        if (!root.palettesSettled)
            return;
        if (root.availablePalettes.length === 0)
            return;
        if (root.availablePalettes.indexOf(ThemeStyle.style) === -1)
            ThemeStyle.setStyle("material");
    }

    onAvailablePalettesChanged: root.reconcileActiveStyle()
    onPalettesSettledChanged: root.reconcileActiveStyle()

    readonly property var dockModeRows: [
        {
            key: "dynamic",
            label: "Dinámico",
            note: "Se oculta y sube al acercar el ratón al borde."
        },
        {
            key: "anchored",
            label: "Anclado",
            note: "Siempre visible y reserva su franja en pantalla."
        }
    ]

    readonly property bool dockAnchored: dockConfig.dockPinned === true

    // Parche mínimo de dock.json: python3 toca sólo "dockPinned" y conserva
    // la lista de apps ancladas que administra el dock. Escritura atómica
    // (a .tmp y renombrando) para que el watcher del dock nunca lea a medias.
    readonly property string dockModePatch: [
        "import json, os, sys",
        "path = sys.argv[1]",
        "wanted = sys.argv[2] == '1'",
        "os.makedirs(os.path.dirname(path), exist_ok=True)",
        "data = {}",
        "try:",
        "    with open(path, encoding='utf-8') as handle:",
        "        loaded = json.load(handle)",
        "    if isinstance(loaded, dict):",
        "        data = loaded",
        "except (OSError, ValueError):",
        "    data = {}",
        "data['dockPinned'] = wanted",
        "tmp = path + '.tmp'",
        "with open(tmp, 'w', encoding='utf-8') as handle:",
        "    json.dump(data, handle)",
        "os.replace(tmp, path)"
    ].join("\n")

    function setDockAnchored(anchored) {
        if (root.dockAnchored === anchored)
            return;
        dockModeWriter.command = [
            "python3", "-c", root.dockModePatch,
            ThemeStyle.configDir + "/dock.json",
            anchored ? "1" : "0"
        ];
        dockModeWriter.running = true;
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

        Text {
            width: parent.width
            text: "Dock"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.fontPx
        }

        Column {
            width: parent.width
            spacing: 8

            Repeater {
                model: root.dockModeRows

                delegate: Rectangle {
                    id: dockModeRow

                    required property var modelData

                    readonly property bool current: root.dockAnchored
                        ? dockModeRow.modelData.key === "anchored"
                        : dockModeRow.modelData.key === "dynamic"

                    width: parent.width
                    height: 52
                    radius: 14
                    color: dockModeRow.current ? Theme.m3Primary : Theme.chip

                    Behavior on color {
                        ColorAnimation { duration: Theme.durFast }
                    }

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: 14
                            right: parent.right
                            rightMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Rectangle {
                            width: 12
                            height: 12
                            radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: dockModeRow.current ? Theme.m3OnPrimary : "transparent"
                            border.width: dockModeRow.current ? 0 : 1
                            border.color: Theme.m3Outline
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 22
                            spacing: 2

                            Text {
                                width: parent.width
                                text: dockModeRow.modelData.label
                                color: dockModeRow.current
                                    ? Theme.m3OnPrimary
                                    : Theme.text
                                font.family: Theme.fontUI
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: dockModeRow.modelData.note
                                color: dockModeRow.current
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
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setDockAnchored(
                            dockModeRow.modelData.key === "anchored")
                    }
                }
            }
        }
    }

    FileView {
        id: dockConfigFile
        path: ThemeStyle.configDir + "/dock.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: dockConfig
            property bool dockPinned: false
        }
    }

    Process {
        id: dockModeWriter
        onExited: dockConfigFile.reload()
    }

    FileView {
        id: materialFile
        path: ThemeStyle.palettePathFor("material")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: root.materialFailed = true

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
        onLoadFailed: root.oledFailed = true

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
        onLoadFailed: root.perlaFailed = true

        JsonAdapter {
            id: perlaAdapter
            property string surfaceContainer: "#211f26"
            property string surfaceContainerHigh: "#2b2930"
            property string primary: "#d0bcff"
        }
    }
}

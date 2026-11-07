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

  El modo día/noche delega en ThemeStyle: activo, el estilo lo elige la hora
  (mañana Perla, tarde Material, noche OLED); manual, se queda el elegido a
  mano. Tocar un estilo mientras está activo lo devuelve a manual.

  Si una paleta no está instalada, su fila queda desactivada con un aviso y
  la paleta activa vuelve a Material para no quedarse sin colores.
*/
Flickable {
    id: root

    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

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
        if (ThemeStyle.autoStyle)
            return;
        if (!root.palettesSettled)
            return;
        if (root.availablePalettes.length === 0)
            return;
        if (root.availablePalettes.indexOf(ThemeStyle.style) === -1)
            ThemeStyle.setStyle("material");
    }

    onAvailablePalettesChanged: root.reconcileActiveStyle()
    onPalettesSettledChanged: root.reconcileActiveStyle()

    readonly property var modeRows: [
        {
            key: "auto",
            label: "Automático",
            note: "06–12 Perla · 12–19 Material · 19–06 OLED."
        },
        {
            key: "manual",
            label: "Manual",
            note: "Eliges el estilo de arriba y se queda."
        }
    ]

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

    function noteFor(rows, key) {
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].key === key)
                return rows[i].note;
        }
        return "";
    }

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
        id: body
        width: root.width
        spacing: 10

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
            visible: UpdateStatus.pending
            text: "Actualización de la shell"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.fontPx
        }

        Rectangle {
            id: updateRow

            visible: UpdateStatus.pending
            width: parent.width
            height: 54
            radius: 14
            color: Theme.m3Primary
            opacity: UpdateStatus.state === "available" && !UpdateStatus.dirty
                ? 1
                : 0.65

            Behavior on opacity {
                NumberAnimation { duration: Theme.durFast }
            }

            Column {
                anchors {
                    left: parent.left
                    leftMargin: 14
                    right: parent.right
                    rightMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2

                Text {
                    width: parent.width
                    text: "Actualizar ahora"
                    color: Theme.m3OnPrimary
                    font.family: Theme.fontUI
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: {
                        if (UpdateStatus.state === "updating")
                            return "Actualizando y reiniciando la shell…";
                        if (UpdateStatus.dirty)
                            return "Tienes cambios locales: actualiza a mano.";
                        if (UpdateStatus.state === "offline")
                            return "Sin conexión; se reintentará solo.";
                        if (UpdateStatus.state === "error")
                            return "No se pudo actualizar; mira update.log.";
                        return UpdateStatus.behind + " commits nuevos en "
                            + UpdateStatus.branch + ".";
                    }
                    color: Theme.m3OnPrimary
                    opacity: 0.85
                    font.family: Theme.fontUI
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: !UpdateStatus.dirty
                    && UpdateStatus.state !== "updating"
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (UpdateStatus.state === "available")
                        UpdateStatus.startUpdate();
                    else
                        UpdateStatus.refresh();
                }
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
                    height: 54
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
                        onClicked: {
                            ThemeStyle.setAutoStyle(false);
                            ThemeStyle.setStyle(row.modelData.key);
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: "Modo día/noche"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.fontPx
        }

        SegmentedChoice {
            width: parent.width
            options: root.modeRows
            value: ThemeStyle.autoStyle ? "auto" : "manual"
            onPicked: (key) => ThemeStyle.setAutoStyle(key === "auto")
        }

        Text {
            width: parent.width
            text: root.noteFor(root.modeRows,
                ThemeStyle.autoStyle ? "auto" : "manual")
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: "Dock"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.fontPx
        }

        SegmentedChoice {
            width: parent.width
            options: root.dockModeRows
            value: root.dockAnchored ? "anchored" : "dynamic"
            onPicked: (key) => root.setDockAnchored(key === "anchored")
        }

        Text {
            width: parent.width
            text: root.noteFor(root.dockModeRows,
                root.dockAnchored ? "anchored" : "dynamic")
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
            elide: Text.ElideRight
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

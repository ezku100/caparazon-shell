import Quickshell
import Quickshell.Io
import QtQuick
import "../../theme"

// Diálogo para vincular, renombrar, recolorear y quitar calendarios de Google.
// Vive dentro de la categoría Calendario (no es una ventana aparte) y habla con
// gcal.py, que es el único dueño de la URL secreta.
Item {
    id: root

    property var calendars: []
    property bool opened: false
    property string statusText: ""
    property bool busy: false

    signal closed()
    signal changed()

    readonly property string scriptPath: String(Qt.resolvedUrl("gcal.py"))
        .replace(/^file:\/\//, "")
    readonly property var palette: [
        "#4285F4", "#EA4335", "#FBBC05", "#34A853",
        "#A142F4", "#24C1E0", "#FF6D01", "#E91E63"
    ]

    property string pendingColor: "#4285F4"
    property string pendingId: ""
    property string pendingMessage: ""

    function close() {
        root.opened = false;
        root.statusText = "";
        root.pendingId = "";
        root.closed();
    }

    function runScript(args, message) {
        root.busy = true;
        root.statusText = "";
        root.pendingMessage = message;
        runner.command = ["python3", root.scriptPath].concat(args);
        runner.running = true;
    }

    function saveNew() {
        if (urlField.text.length === 0) {
            root.statusText = "Pega la dirección iCal de tu calendario";
            return;
        }
        const args = ["set-url", urlField.text];
        if (nameField.text.length > 0)
            args.push("--name", nameField.text);
        args.push("--color", root.pendingColor);
        root.runScript(args, "Calendario vinculado");
    }

    function toggleEnabled(calendar) {
        root.runScript(
            ["set-enabled", calendar.id, calendar.enabled ? "false" : "true"],
            calendar.enabled ? "Calendario desactivado" : "Calendario activado"
        );
    }

    function removeCalendar(calendar) {
        root.runScript(["remove", calendar.id], "Calendario quitado");
    }

    function pickColor(color) {
        if (root.pendingId.length > 0) {
            root.runScript(
                ["set-color", root.pendingId, color], "Color actualizado");
            root.pendingId = "";
            return;
        }
        root.pendingColor = color;
    }

    Rectangle {
        anchors.fill: parent
        color: "#66000000"
        visible: root.opened

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 380
        height: 340
        radius: 20
        color: Theme.m3SurfaceContainerHigh
        border.width: 1
        border.color: Theme.m3OutlineVariant
        visible: root.opened

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Item {
                id: header
                width: parent.width
                height: 20

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Vincular calendarios"
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }
            }

            Item {
                width: parent.width
                height: Math.max(0, root.calendars.length * 26)

                Repeater {
                    model: root.calendars

                    delegate: Item {
                        required property var modelData
                        width: header.width
                        height: 26

                        Rectangle {
                            id: swatch
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10
                            height: 10
                            radius: 5
                            color: modelData.color

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.pendingId = modelData.id
                            }
                        }

                        TextInput {
                            id: nameInput
                            anchors.left: swatch.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 130
                            text: modelData.name
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: 10
                            selectByMouse: true
                            onEditingFinished: {
                                if (text !== modelData.name)
                                    root.runScript(
                                        ["set-name", modelData.id, text],
                                        "Nombre actualizado");
                            }
                        }

                        Text {
                            anchors.left: nameInput.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.ical_tail
                            color: Theme.textDim
                            font.family: Theme.fontUI
                            font.pixelSize: 9
                        }

                        Text {
                            anchors.right: removeLabel.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.enabled ? "activo" : "inactivo"
                            color: Theme.textDim
                            font.family: Theme.fontUI
                            font.pixelSize: 9

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.toggleEnabled(modelData)
                            }
                        }

                        Text {
                            id: removeLabel
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Quitar"
                            color: Theme.textDim
                            font.family: Theme.fontUI
                            font.pixelSize: 9

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.removeCalendar(modelData)
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairline
            }

            Text {
                text: "Nuevo calendario"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }

            Item {
                width: parent.width
                height: 16

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: nameField.text.length === 0
                    text: "Nombre (opcional)"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 10
                }

                TextInput {
                    id: nameField
                    anchors.fill: parent
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 10
                    selectByMouse: true
                }
            }

            Item {
                width: parent.width
                height: 16

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: urlField.text.length === 0
                    text: "Dirección iCal"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 10
                }

                TextInput {
                    id: urlField
                    anchors.fill: parent
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 10
                    selectByMouse: true
                }
            }

            Row {
                spacing: 8

                Text {
                    text: "Pegar"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 10

                    MouseArea {
                        anchors.fill: parent
                        onClicked: paste.running = true
                    }
                }

                Text {
                    text: "Guardar"
                    color: Theme.m3Primary
                    font.family: Theme.fontUI
                    font.pixelSize: 10
                    font.weight: Font.DemiBold

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.saveNew()
                    }
                }

                Text {
                    text: "Abrir ajustes de Google"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 10

                    MouseArea {
                        anchors.fill: parent
                        onClicked: openSettings.running = true
                    }
                }
            }

            Row {
                spacing: 6

                Text {
                    text: root.pendingId.length > 0 ? "Color del calendario" : "Color"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 9
                }

                Repeater {
                    model: root.palette

                    delegate: Rectangle {
                        required property var modelData
                        width: 12
                        height: 12
                        radius: 6
                        color: modelData

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.pickColor(modelData)
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.statusText
                color: root.statusText.length > 0 ? Theme.m3Error : Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 9
                wrapMode: Text.WordWrap
            }
        }
    }

    Process {
        id: paste
        command: ["wl-paste", "--no-newline"]

        stdout: StdioCollector {
            onStreamFinished: urlField.text = String(text || "").trim();
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.opened
        onActivated: root.close()
    }

    Process {
        id: openSettings
        command: ["xdg-open", "https://calendar.google.com/calendar/settings"]
    }

    Process {
        id: runner

        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                const raw = String(text || "").trim();
                if (!raw)
                    return;
                try {
                    const data = JSON.parse(raw);
                    if (data && data.ok) {
                        root.statusText = root.pendingMessage;
                        urlField.text = "";
                        nameField.text = "";
                        root.changed();
                    } else {
                        root.statusText = data && data.error
                            ? data.error
                            : "No se pudo completar la operación";
                    }
                } catch (error) {
                    root.statusText = "No se pudo leer la respuesta del script";
                }
            }
        }
    }
}

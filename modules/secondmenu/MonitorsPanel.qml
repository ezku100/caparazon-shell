import Quickshell
import Quickshell.Io
import QtQuick
import "../../theme"

Item {
    id: root

    property var outputs: []
    property var draft: ({})
    property string selectedName: ""
    property string primaryName: ""
    property string pendingJson: ""
    property string errorMessage: ""
    property string noticeMessage: ""
    property bool applying: false
    property bool resolutionsOpen: false

    Component.onCompleted: load.running = true

    function applyState(payload) {
        let data = null;
        try {
            data = JSON.parse(String(payload || ""));
        } catch (error) {
            root.errorMessage = "No se pudo leer el estado de monitores";
            return;
        }
        if (!data)
            return;
        if (data.error && String(data.error).length > 0) {
            root.errorMessage = String(data.error);
            root.outputs = [];
            root.draft = ({});
            root.selectedName = "";
            root.primaryName = "";
            return;
        }
        root.outputs = Array.isArray(data.outputs) ? data.outputs : [];
        const previousSelection = root.selectedName;
        const next = ({});
        let primary = "";
        for (let index = 0; index < root.outputs.length; index++) {
            const output = root.outputs[index];
            next[output.name] = {
                mode: output.mode || "",
                transform: output.transform || "normal",
                x: output.x || 0,
                y: output.y || 0
            };
            if (output.primary && !primary)
                primary = output.name;
        }
        root.draft = next;
        root.primaryName = primary || (root.outputs.length > 0 ? root.outputs[0].name : "");
        root.selectedName = next[previousSelection] ? previousSelection : root.primaryName;
        root.errorMessage = "";
        root.noticeMessage = data.configured ? "" : "La configuración de monitores aún no existe.";
        root.syncPositionInputs();
    }

    function selectedOutput() {
        for (let index = 0; index < root.outputs.length; index++) {
            if (root.outputs[index].name === root.selectedName)
                return root.outputs[index];
        }
        return null;
    }

    function selectedDraft() {
        if (!root.selectedName || !root.draft)
            return null;
        return root.draft[root.selectedName] || null;
    }

    function selectedModeLabel() {
        const draft = root.selectedDraft();
        if (draft && draft.mode)
            return draft.mode;
        const output = root.selectedOutput();
        if (output && output.mode)
            return output.mode;
        return "Sin monitores";
    }

    function transformKey(value) {
        if (value === "90" || value === "flipped-90")
            return "90";
        if (value === "180" || value === "flipped-180")
            return "180";
        if (value === "270" || value === "flipped-270")
            return "270";
        return "normal";
    }

    function patchSelected(changes) {
        const name = root.selectedName;
        if (!name || !root.draft[name])
            return;
        const next = JSON.parse(JSON.stringify(root.draft));
        for (const key in changes) {
            if (Object.prototype.hasOwnProperty.call(changes, key))
                next[name][key] = changes[key];
        }
        root.draft = next;
    }

    function commitPosition(axis, input) {
        const value = parseInt(String(input.text).trim(), 10);
        if (isNaN(value))
            return;
        const changes = {};
        changes[axis] = value;
        root.patchSelected(changes);
    }

    function syncPositionInputs() {
        if (!xInput || !yInput)
            return;
        const draft = root.selectedDraft();
        xInput.text = draft ? String(draft.x) : "0";
        yInput.text = draft ? String(draft.y) : "0";
    }

    function choosePrimary() {
        if (!root.selectedName || root.applying || root.primaryName === root.selectedName)
            return;
        root.primaryName = root.selectedName;
        root.errorMessage = "";
        root.noticeMessage = "Principal marcado; aplica para guardarlo.";
    }

    function prepareApply() {
        if (!root.primaryName || root.applying)
            return;
        commitPosition("x", xInput);
        commitPosition("y", yInput);
        const items = [];
        for (let index = 0; index < root.outputs.length; index++) {
            const name = root.outputs[index].name;
            const value = root.draft[name];
            if (!value)
                continue;
            items.push({
                name: name,
                mode: value.mode,
                transform: value.transform,
                x: value.x,
                y: value.y
            });
        }
        root.pendingJson = JSON.stringify({ primary: root.primaryName, outputs: items });
        root.errorMessage = "";
        root.noticeMessage = "";
        root.applying = true;
        apply.running = true;
    }

    Process {
        id: load

        command: ["caparazon-wm", "monitors"]

        stdout: StdioCollector {
            onStreamFinished: root.applyState(text)
        }

        stderr: StdioCollector {
            onStreamFinished: root.errorMessage = String(text || "").trim()
        }
    }

    Process {
        id: apply

        command: ["caparazon-wm", "monitors", "--apply", root.pendingJson]

        stderr: StdioCollector {
            onStreamFinished: root.errorMessage = String(text || "").trim()
        }

        onExited: (exitCode) => {
            root.applying = false;
            if (exitCode === 0) {
                root.noticeMessage = "Configuración aplicada.";
                load.running = true;
                ShellLayout.refreshPrimary();
            } else if (root.errorMessage.length === 0) {
                root.errorMessage = "No se pudo aplicar la configuración";
            }
        }
    }

    implicitHeight: content.implicitHeight + 12

    Column {
        id: content

        width: root.width
        spacing: 8

            Text {
                width: parent.width
                text: "Monitores"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: "Salidas detectadas en niri. Los cambios se guardan al aplicar."
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Row {
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.outputs

                    delegate: Rectangle {
                        required property var modelData

                        readonly property bool active: modelData.name === root.selectedName
                        readonly property bool primary: modelData.name === root.primaryName

                        width: Math.max(96, (content.width - 6) / Math.max(1, root.outputs.length) - 6)
                        height: 40
                        radius: Theme.radius
                        color: active ? Theme.m3SurfaceContainerHighest : Theme.chip
                        border.width: active ? 2 : 0
                        border.color: active ? Theme.m3Primary : Theme.m3OutlineVariant

                        Text {
                            anchors {
                                fill: parent
                                margins: 4
                            }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.label
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: 11
                            font.weight: active ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            anchors {
                                top: parent.top
                                right: parent.right
                                topMargin: 2
                                rightMargin: 4
                            }
                            text: "●"
                            color: Theme.m3Primary
                            font.family: Theme.fontUI
                            font.pixelSize: 8
                            visible: primary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedName = modelData.name;
                                root.errorMessage = "";
                                root.noticeMessage = "";
                                root.syncPositionInputs();
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.selectedOutput() ? root.selectedOutput().label : "Sin monitores"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Rectangle {
                width: 96
                height: 28
                radius: Theme.radius
                color: root.primaryName && root.primaryName === root.selectedName
                    ? Theme.m3Primary
                    : Theme.chip
                enabled: root.selectedName.length > 0 && !root.applying

                Text {
                    anchors.centerIn: parent
                    text: "Principal"
                    color: root.primaryName && root.primaryName === root.selectedName
                        ? Theme.m3OnPrimary
                        : Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 11
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choosePrimary()
                }
            }

            Text {
                width: parent.width
                text: "Resolución y tasa"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
            }

            Rectangle {
                width: parent.width
                height: 30
                radius: Theme.radius
                color: Theme.chip

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 8
                        rightMargin: 28
                    }
                    text: root.selectedModeLabel()
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Text {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 10
                    }
                    text: root.resolutionsOpen ? "▴" : "▾"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 11
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resolutionsOpen = !root.resolutionsOpen
                }
            }

            Column {
                width: parent.width
                height: root.resolutionsOpen ? modesList.implicitHeight : 0
                clip: true
                visible: root.resolutionsOpen

                Column {
                    id: modesList

                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.selectedOutput() ? root.selectedOutput().modes : []

                        delegate: Rectangle {
                            required property var modelData

                            readonly property bool active:
                                root.selectedDraft() && root.selectedDraft().mode === modelData.label

                            width: parent.width
                            height: 28
                            radius: Theme.radius
                            color: active ? Theme.m3SurfaceContainerHighest : Theme.chip
                            border.width: active ? 2 : 0
                            border.color: Theme.m3Primary

                            Text {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 8
                                    rightMargin: 8
                                }
                                text: modelData.label
                                    + (modelData.preferred ? "  · preferido" : "")
                                    + (modelData.current ? "  · actual" : "")
                                color: Theme.text
                                font.family: Theme.fontUI
                                font.pixelSize: 11
                                font.weight: active ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.patchSelected({ mode: modelData.label })
                                    root.resolutionsOpen = false
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "Rotación"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
            }

            SegmentedChoice {
                width: parent.width
                options: [
                    { key: "normal", label: "Normal" },
                    { key: "90", label: "90°" },
                    { key: "180", label: "180°" },
                    { key: "270", label: "270°" }
                ]
                value: root.selectedDraft() ? root.transformKey(root.selectedDraft().transform) : "normal"
                onPicked: (key) => root.patchSelected({ transform: key })
            }

            Text {
                width: parent.width
                text: "Posición"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
            }

            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 28
                    radius: Theme.radius
                    color: Theme.chip

                    Text {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                        }
                        text: "x"
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: xInput

                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 24
                            rightMargin: 8
                        }
                        text: "0"
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: 11
                        validator: IntValidator { bottom: -10000; top: 10000 }
                        onEditingFinished: root.commitPosition("x", xInput)
                    }
                }

                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 28
                    radius: Theme.radius
                    color: Theme.chip

                    Text {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                        }
                        text: "y"
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: yInput

                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 24
                            rightMargin: 8
                        }
                        text: "0"
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: 11
                        validator: IntValidator { bottom: -10000; top: 10000 }
                        onEditingFinished: root.commitPosition("y", yInput)
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: Theme.radius
                color: root.applying ? Theme.chip : Theme.m3Primary
                enabled: root.primaryName.length > 0 && !root.applying

                Text {
                    anchors.centerIn: parent
                    text: root.applying ? "Aplicando…" : "Aplicar"
                    color: root.applying ? Theme.text : Theme.m3OnPrimary
                    font.family: Theme.fontUI
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.prepareApply()
                }
            }

            Text {
                width: parent.width
                text: root.errorMessage.length > 0 ? root.errorMessage : root.noticeMessage
                color: root.errorMessage.length > 0 ? Theme.m3Error : Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
}

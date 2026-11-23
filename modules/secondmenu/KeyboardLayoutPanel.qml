import Quickshell
import Quickshell.Io
import QtQuick
import "../../theme"

Item {
    id: root

    property var languages: []
    property string layout: ""
    property string variant: ""
    property string label: ""
    property string pendingLayout: ""
    property string pendingVariant: ""
    property string pendingLabel: ""
    property string errorMessage: ""
    property string noticeMessage: ""
    property bool applying: false

    implicitHeight: content.implicitHeight + 12

    Component.onCompleted: load.running = true

    function applyState(payload) {
        let data = null;
        try {
            data = JSON.parse(String(payload || ""));
        } catch (error) {
            root.errorMessage = "No se pudo leer el idioma de teclado";
            return;
        }
        if (!data)
            return;
        root.languages = Array.isArray(data.languages) ? data.languages : [];
        root.layout = data.layout || "";
        root.variant = data.variant || "";
        root.label = data.label || "";
        root.pendingLayout = root.layout;
        root.pendingVariant = root.variant;
        root.pendingLabel = root.label;
    }

    function optionKey(layout, variant) {
        return layout + "/" + variant;
    }

    function currentLanguage() {
        for (const language of root.languages) {
            if (!Array.isArray(language.options))
                continue;
            for (const option of language.options) {
                if (option.layout === root.pendingLayout
                        && option.variant === root.pendingVariant)
                    return language;
            }
        }
        return null;
    }

    function currentLanguageLabel() {
        const language = root.currentLanguage();
        return language ? language.label : "Otra configuración";
    }

    function currentOptionKey() {
        return root.optionKey(root.pendingLayout, root.pendingVariant);
    }

    function currentLanguageOptions() {
        const language = root.currentLanguage();
        if (!language)
            return [];
        return language.options.map((option) => ({
            key: root.optionKey(option.layout, option.variant),
            label: option.label
        }));
    }

    function chooseLanguage(index) {
        if (root.applying || index < 0 || index >= root.languages.length)
            return;
        const language = root.languages[index];
        if (!Array.isArray(language.options) || language.options.length === 0)
            return;
        const option = language.options[0];
        root.errorMessage = "";
        root.noticeMessage = "";
        root.pendingLayout = option.layout;
        root.pendingVariant = option.variant;
        root.pendingLabel = language.label + " · " + option.label;
    }

    function chooseVariant(key) {
        if (root.applying)
            return;
        const language = root.currentLanguage();
        if (!language)
            return;
        for (const option of language.options) {
            if (root.optionKey(option.layout, option.variant) === key) {
                root.errorMessage = "";
                root.noticeMessage = "";
                root.pendingLayout = option.layout;
                root.pendingVariant = option.variant;
                root.pendingLabel = language.label + " · " + option.label;
                return;
            }
        }
    }

    function hasPendingChange() {
        return root.pendingLayout !== root.layout
            || root.pendingVariant !== root.variant;
    }

    function applyKeyboard() {
        if (root.applying || !root.hasPendingChange())
            return;
        root.errorMessage = "";
        root.noticeMessage = "";
        root.applying = true;
        const args = ["caparazon-wm", "keyboard-layout", "--set", root.pendingLayout];
        if (root.pendingVariant.length > 0)
            args.push(root.pendingVariant);
        apply.command = args;
        apply.running = true;
    }

    Process {
        id: load

        command: ["caparazon-wm", "keyboard-layout"]

        stdout: StdioCollector {
            onStreamFinished: root.applyState(text)
        }
    }

    Process {
        id: apply

        command: ["caparazon-wm", "keyboard-layout", "--set"]

        stderr: StdioCollector {
            onStreamFinished: root.errorMessage = String(text || "").trim()
        }

        onExited: (exitCode) => {
            root.applying = false;
            if (exitCode === 0) {
                root.layout = root.pendingLayout;
                root.variant = root.pendingVariant;
                root.label = root.pendingLabel;
                root.noticeMessage = "Teclado aplicado.";
            } else if (root.errorMessage.length === 0) {
                root.errorMessage = "No se pudo aplicar el teclado";
            }
        }
    }

    Column {
        id: content

        width: parent.width
        spacing: 8

        Text {
            width: parent.width
            text: "Idioma de teclado"
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            text: "Distribución usada por niri al escribir."
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: "Idioma"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
        }

        Grid {
            id: grid

            width: parent.width
            columns: Math.max(1, Math.floor(width / 132))
            spacing: 6

            readonly property int cellWidth: Math.floor(
                (width - (columns - 1) * spacing) / columns
            )

            Repeater {
                model: root.languages

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: grid.cellWidth
                    height: 34
                    radius: 10
                    color: root.currentLanguageLabel() === modelData.label
                        ? Theme.m3Primary
                        : Theme.chip

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.color === Theme.m3Primary
                            ? Theme.m3OnPrimary
                            : Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chooseLanguage(index)
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: "Variación"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
        }

        SegmentedChoice {
            width: parent.width
            options: root.currentLanguageOptions()
            value: root.currentOptionKey()
            onPicked: (key) => root.chooseVariant(key)
        }

        Text {
            width: parent.width
            text: "Aplicado: " + (root.label || root.pendingLabel || "—")
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Rectangle {
            width: parent.width
            height: 38
            radius: 12
            color: !root.applying && root.hasPendingChange()
                ? Theme.m3Primary
                : Theme.chip

            Text {
                anchors.centerIn: parent
                text: root.applying ? "Aplicando…" : "Aplicar teclado"
                color: !root.applying && root.hasPendingChange()
                    ? Theme.m3OnPrimary
                    : Theme.m3OnSurfaceVariant
                font.family: Theme.fontUI
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            MouseArea {
                anchors.fill: parent
                enabled: !root.applying && root.hasPendingChange()
                cursorShape: Qt.PointingHandCursor
                onClicked: root.applyKeyboard()
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

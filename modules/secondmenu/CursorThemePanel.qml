import Quickshell
import Quickshell.Io
import QtQuick
import "../../theme"

Item {
    id: root

    property var themes: []
    property string current: ""
    property string defaultTheme: ""
    property string pendingTheme: ""
    property string errorMessage: ""
    property string noticeMessage: ""
    property bool applying: false

    implicitHeight: footer.y + footer.height + 8

    Component.onCompleted: load.running = true

    function applyState(payload) {
        let data = null;
        try {
            data = JSON.parse(String(payload || ""));
        } catch (error) {
            root.errorMessage = "No se pudo leer la lista de cursores";
            return;
        }
        if (!data)
            return;
        root.themes = Array.isArray(data.themes) ? data.themes : [];
        root.current = data.current || "";
        root.defaultTheme = data.default || "";
    }

    function choose(theme) {
        if (theme === root.current || root.applying)
            return;
        root.errorMessage = "";
        root.noticeMessage = "";
        root.pendingTheme = theme;
        root.applying = true;
        apply.running = true;
    }

    Process {
        id: load

        command: ["caparazon-wm", "cursor-theme"]

        stdout: StdioCollector {
            onStreamFinished: root.applyState(text)
        }
    }

    Process {
        id: apply

        command: ["caparazon-wm", "cursor-theme", "--set", root.pendingTheme]

        stderr: StdioCollector {
            onStreamFinished: root.errorMessage = String(text || "").trim()
        }

        onExited: (exitCode) => {
            root.applying = false;
            if (exitCode === 0) {
                root.current = root.pendingTheme;
                root.noticeMessage = "Cursor aplicado.";
            } else if (root.errorMessage.length === 0) {
                root.errorMessage = "No se pudo aplicar el cursor";
            }
        }
    }

    Text {
        id: title

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        text: "Tema del cursor"
        color: Theme.text
        font.family: Theme.fontUI
        font.pixelSize: 16
        font.weight: Font.DemiBold
    }

    Text {
        id: subtitle

        anchors {
            left: parent.left
            right: parent.right
            top: title.bottom
            topMargin: 2
        }
        text: "El aspecto del puntero en la sesión niri."
        color: Theme.textDim
        font.family: Theme.fontUI
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    Grid {
        id: grid

        anchors {
            left: parent.left
            right: parent.right
            top: subtitle.bottom
            topMargin: 12
        }
        columns: Math.max(1, Math.floor(width / 128))

        readonly property int cellWidth: Math.floor(width / columns)
        readonly property int cellHeight: 104

        Repeater {
            model: root.themes

            delegate: Item {
                id: cell

                required property string modelData

                readonly property bool active: cell.modelData === root.current

                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors {
                        fill: parent
                        margins: 4
                    }
                    radius: Theme.radius
                    color: cell.active ? Theme.m3SurfaceContainerHigh : "transparent"
                    border.width: cell.active ? 1 : 0
                    border.color: Theme.m3OutlineVariant
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "↖"
                        color: cell.active ? Theme.text : Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 34
                    }

                    Text {
                        width: grid.cellWidth - 16
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.modelData
                        color: cell.active ? Theme.text : Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 11
                        font.weight: cell.active ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(cell.modelData)
                }
            }
        }
    }

    Item {
        id: footer

        anchors {
            left: parent.left
            right: parent.right
            top: grid.bottom
            topMargin: 8
        }
        height: Math.max(18, footerText.implicitHeight)

        Text {
            id: footerText

            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            text: root.errorMessage.length > 0 ? root.errorMessage : root.noticeMessage
            color: root.errorMessage.length > 0 ? Theme.m3Error : Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
}

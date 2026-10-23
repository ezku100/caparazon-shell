import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import "../../theme"

// Menú contextual de las apps del dock. Reutiliza el lenguaje visual del
// menú de bandeja: burbuja M3, sombra suave, filas de 40 px y cola inferior.
PopupWindow {
    id: root

    property Item anchorItem: null
    property var app: null
    // DesktopEntry resuelto por Dock.qml; de aquí salen las DesktopAction.
    property var entry: null
    property bool pinned: false
    property bool opened: false
    property var menuState: null

    property int menuWidth: 252
    property bool showArrow: true

    readonly property int arrowW: 16
    readonly property int arrowH: 8
    readonly property int bleed: 14
    readonly property int topPad: bleed
    readonly property real arrowCenter: menuWidth / 2

    readonly property int maxMenuHeight: Math.min(360, (screen ? screen.height : 1080) - 160)

    readonly property var entries: {
        const items = [];
        if (!root.app)
            return items;

        items.push(root.pinned
            ? { key: "unpin", text: "Desanclar del dock", icon: "non-starred" }
            : { key: "pin", text: "Anclar al dock", icon: "starred" });

        // Acciones estándar del .desktop: New Window, New Private Window,
        // Open Profile Manager, etc. Se muestran para cualquier app que las
        // declare; no hay casos hardcodeados por aplicación.
        const actions = root.entry && root.entry.actions
            ? root.entry.actions
            : [];
        let hasNewWindowAction = false;
        for (let i = 0; i < actions.length; ++i) {
            const action = actions[i];
            if (!action || !action.name
                    || !action.command || action.command.length === 0)
                continue;
            if (action.id === "new-window")
                hasNewWindowAction = true;
            items.push({
                key: "action:" + (action.id || i),
                text: action.name,
                icon: action.icon || "application-x-executable",
                action: action
            });
        }

        // Respaldo para apps sin acción "new-window" declarada.
        if (!hasNewWindowAction
                && root.app.newCommand && root.app.newCommand.length > 0)
            items.push({ key: "new", text: "Abrir nueva ventana", icon: "window-new" });

        return items;
    }

    signal pinRequested()
    signal unpinRequested()
    signal newWindowRequested()

    function open() {
        if (opened || !anchorItem)
            return;
        if (menuState && typeof menuState.activate === "function")
            menuState.activate(root);
        opened = true;
    }

    function close() {
        if (!opened)
            return;
        opened = false;
        if (menuState && typeof menuState.deactivate === "function")
            menuState.deactivate(root);
    }

    function activate(entry) {
        if (!entry)
            return;
        if (entry.key === "pin")
            root.pinRequested();
        else if (entry.key === "unpin")
            root.unpinRequested();
        else if (entry.key === "new")
            root.newWindowRequested();
        else if (entry.action && typeof entry.action.execute === "function")
            entry.action.execute();
        close();
    }

    visible: opened
    color: "transparent"
    // Igual que TrayMenu: sin grabFocus la ventana es Qt::ToolTip y no se
    // come los clics del dock. El cierre exterior lo hace el catcher del Dock.
    grabFocus: false

    anchor.item: root.anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Top
    anchor.adjustment: PopupAdjustment.SlideX

    // El dock mide 52 px y la app 44 px: su borde superior queda 4 px por
    // debajo del borde real del dock. El popup termina 6 px por encima del
    // icono; la cola ocupa los 8 px restantes.
    readonly property real anchorY: anchorItem
        ? -(Theme.dockHeight - anchorItem.height) / 2 - 6
        : 0

    anchor.rect.x: anchorItem ? anchorItem.width / 2 : 0
    anchor.rect.y: root.anchorY
    anchor.rect.width: 1
    anchor.rect.height: 1

    implicitWidth: menuWidth + bleed * 2
    implicitHeight: topPad + body.height + arrowH

    // Sólo la burbuja captura clics, no el margen transparente.
    mask: Region { item: body }

    onClosed: close()

    Shortcut {
        sequence: "Escape"
        enabled: root.opened
        onActivated: root.close()
    }

    Item {
        id: content
        anchors.fill: parent

        opacity: root.opened ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        Item {
            id: body
            x: root.bleed
            y: root.topPad
            width: root.menuWidth
            height: Math.max(40, Math.min(menuColumn.implicitHeight + 12,
                root.maxMenuHeight))

            MultiEffect {
                source: bubble
                anchors.fill: bubble
                blurMax: 24
                shadowEnabled: true
                shadowColor: Theme.shadowColor
                shadowOpacity: 0.20
                shadowBlur: 0.32
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 3
            }

            Rectangle {
                id: bubble
                anchors.fill: parent
                radius: 16
                color: Theme.surface
            }

            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: menuColumn.implicitHeight + 12
                interactive: contentHeight > height

                Column {
                    id: menuColumn
                    x: 0
                    y: 6
                    width: flick.width

                    Repeater {
                        model: root.entries

                        delegate: Item {
                            id: entry
                            required property var modelData
                            width: menuColumn.width
                            height: 40

                            Rectangle {
                                id: hoverPill
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 8
                                color: hover.hovered ? Theme.chipHover : "transparent"
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors {
                                    leftMargin: 14
                                    rightMargin: 12
                                }
                                spacing: 10

                                IconImage {
                                    implicitSize: 16
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: Quickshell.iconPath(entry.modelData.icon,
                                        "application-x-executable")
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: entry.modelData.text
                                    color: Theme.m3OnSurface
                                    font.family: Theme.fontUI
                                    font.pixelSize: Theme.fontPx
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            HoverHandler {
                                id: hover
                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activate(entry.modelData)
                            }
                        }
                    }
                }
            }
        }

        // Cola inferior: apunta al icono del dock.
        Shape {
            id: tail
            visible: root.showArrow
            x: Math.round(root.bleed + root.arrowCenter - root.arrowW / 2)
            y: body.y + body.height
            width: root.arrowW
            height: root.arrowH + 1
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: bubble.color
                startX: 0
                startY: 0
                PathLine { x: tail.width / 2; y: tail.height }
                PathLine { x: tail.width; y: 0 }
                PathLine { x: 0; y: 0 }
            }
        }
    }
}

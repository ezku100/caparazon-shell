import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../../theme"
import "../icons"

// Menú contextual de las apps del dock. Reutiliza el lenguaje visual del
// menú de bandeja: burbuja M3, sombra suave y filas de 40 px. Sin cola: la
// burbuja se abre hacia el lado interior del icono sea cual sea el borde
// donde viva el dock.
PopupWindow {
    id: root

    property Item anchorItem: null
    property var app: null
    // DesktopEntry resuelto por Dock.qml; de aquí salen las DesktopAction.
    property var entry: null
    property bool pinned: false
    property bool opened: false
    property var menuState: null
    // Borde de la pantalla donde está el dock: "bottom", "top", "left" o
    // "right". Decide hacia dónde crece la burbuja.
    property string placement: "bottom"

    property int menuWidth: 252

    // Aire transparente alrededor de la burbuja: la sombra del MultiEffect
    // necesita ese margen para no quedar recortada. Es simétrico, de modo
    // que la burbuja se ve a la misma distancia del cristal en los cuatro
    // bordes.
    readonly property int bleed: 14
    // Separación visible entre el cristal del dock y la burbuja.
    readonly property int gap: 6
    // Punto de anclaje: se mete dentro del icono lo que sobra después de
    // descontar `bleed`, y así la burbuja queda a `gap` del cristal en vez
    // de a `bleed + gap`.
    readonly property int anchorInset: Math.max(0, bleed - gap)

    readonly property bool atTop: placement === "top"
    readonly property bool atLeft: placement === "left"
    readonly property bool atRight: placement === "right"
    readonly property bool side: atLeft || atRight

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

    // La burbuja se pega al cristal por el lado interior del icono:
    //   bottom -> crece hacia arriba (ancla en el borde superior del icono)
    //   top    -> crece hacia abajo  (ancla en el borde inferior)
    //   left   -> crece hacia la derecha (ancla en el borde derecho)
    //   right  -> crece hacia la izquierda (ancla en el borde izquierdo)
    // En los laterales la primera fila queda alineada con la parte alta
    // del icono, como en un menú de contexto normal.
    anchor.item: root.anchorItem
    anchor.edges: root.atTop
        ? Edges.Top
        : root.side
            ? (root.atLeft ? (Edges.Left | Edges.Top) : (Edges.Right | Edges.Top))
            : Edges.Bottom
    anchor.gravity: root.atTop
        ? Edges.Bottom
        : root.side
            ? (root.atLeft ? (Edges.Right | Edges.Bottom) : (Edges.Left | Edges.Bottom))
            : Edges.Top
    anchor.adjustment: root.side
        ? PopupAdjustment.SlideY
        : PopupAdjustment.SlideX

    anchor.rect.x: !root.anchorItem
        ? 0
        : root.side
            ? (root.atLeft
                ? root.anchorItem.width - root.anchorInset
                : root.anchorInset)
            : root.anchorItem.width / 2
    anchor.rect.y: !root.anchorItem
        ? 0
        : root.side
            ? -root.anchorInset
            : (root.atTop
                ? root.anchorItem.height - root.anchorInset
                : root.anchorInset)
    anchor.rect.width: 1
    anchor.rect.height: 1

    implicitWidth: menuWidth + bleed * 2
    implicitHeight: body.height + bleed * 2

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
            y: root.bleed
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
                                    source: IconResolver.source(entry.modelData.icon,
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
    }
}

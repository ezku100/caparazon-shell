import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import "../../theme"

// Menú de bandeja propio: burbuja Material 3 con cola superior.
// QMenu nativo no se puede estilizar, así que dibujamos el menú en QML
// usando QsMenuOpener (datos DBusMenu) y PopupWindow (superficie Wayland).
PopupWindow {
    id: root

    required property var menuHandle
    required property Item anchorItem

    // Menú padre cuando este es un submenú. Permite cerrar toda la cadena.
    property var parentMenu: null
    // El menú raíz lleva cola; los submenús son burbujas limpias sin cola.
    property bool showArrow: true
    property bool opened: false
    // El puntero está dentro de la burbuja; el icono de la bandeja lo usa
    // para no cerrar el menú al pasar del icono a la burbuja.
    property bool menuHovered: false
    property int menuWidth: 252
    property var menuState: null
    // El menú raíz cuelga hacia abajo; los submenús se abren a la izquierda.
    property int anchorEdge: Edges.Top
    property int anchorGravity: Edges.Bottom
    property int anchorAdjustment: PopupAdjustment.SlideX

    readonly property int arrowW: 16
    readonly property int arrowH: 8
    readonly property int bleed: 14
    // Sin aire arriba cuando hay cola: la punta debe tocar la barra.
    readonly property int topPad: showArrow ? 0 : bleed
    property real arrowCenter: width / 2
    property var childMenu: null

    readonly property int maxMenuHeight: Math.min(720, (screen ? screen.height : 1080) - 160)

    signal activated()
    signal submenuRequested(var handle, var anchor)

    function notifyOpened(handle) {
        if (!handle)
            return;
        if (typeof handle.sendOpened === "function")
            handle.sendOpened();
        else if (handle.menu && typeof handle.menu.sendOpened === "function")
            handle.menu.sendOpened();
    }

    function notifyClosed(handle) {
        if (!handle)
            return;
        if (typeof handle.sendClosed === "function")
            handle.sendClosed();
        else if (handle.menu && typeof handle.menu.sendClosed === "function")
            handle.menu.sendClosed();
    }

    function open() {
        if (opened || !menuHandle)
            return;
        if (menuState && typeof menuState.activate === "function")
            menuState.activate(root);
        opened = true;
        notifyOpened(menuHandle);
        Qt.callLater(updateArrow);
    }

    function close() {
        if (childMenu) {
            const child = childMenu;
            childMenu = null;
            child.close();
        }
        if (!opened)
            return;
        opened = false;
        menuHovered = false;
        if (menuState && typeof menuState.deactivate === "function")
            menuState.deactivate(root);
        notifyClosed(menuHandle);
        if (parentMenu && parentMenu.childMenu === root)
            parentMenu.childMenu = null;
    }

    function toggle() {
        opened ? close() : open();
    }

    function openChild(menu) {
        if (!menu)
            return;
        if (childMenu && childMenu !== menu)
            childMenu.close();
        childMenu = menu;
        menu.open();
    }

    // Menú raíz de la cadena (el que tiene la cola y el icono de la barra).
    function topMenu() {
        let menu = root;
        while (menu.parentMenu)
            menu = menu.parentMenu;
        return menu;
    }

    function activateEntry(entry) {
        if (!entry || entry.isSeparator || !entry.enabled)
            return;
        if (entry.hasChildren)
            return;
        // DBusMenuItem expone sendTriggered(); QsMenuEntry.triggered es una
        // señal que el backend emite al activar, no un método de activación.
        if (typeof entry.sendTriggered === "function")
            entry.sendTriggered();
        else if (typeof entry.triggered === "function")
            entry.triggered();
        activated();
        close();
    }

    // El menú está centrado bajo el icono, así que la cola debe quedar en el
    // centro del cuerpo. mapFromItem() en un PopupWindow añade el bleed y
    // desplazaba la cola hacia la derecha.
    function updateArrow() {
        if (!showArrow || !width)
            return;
        arrowCenter = width / 2 - bleed;
    }

    visible: opened
    color: "transparent"
    // Sin grabFocus, Quickshell crea la ventana como Qt::ToolTip y NO
    // como Qt::Popup. Un Qt::Popup se queda con el puntero y se come los
    // clics de la barra y de los demás iconos; por eso el menú no se
    // cerraba y cambiar de icono requería dos clics.
    grabFocus: false

    anchor.item: anchorItem
    anchor.edges: anchorEdge
    anchor.gravity: anchorGravity
    anchor.adjustment: anchorAdjustment

    // El icono mide 26 px y está centrado en la barra de 40 px: su borde
    // inferior queda 7 px por encima del borde real. Anclamos el popup al
    // borde inferior de la barra, no al del icono.
    readonly property real barBottomInItem: anchorItem
        ? (Theme.barHeight + anchorItem.height) / 2
        : 0

    // Punto de anclaje en el centro horizontal del icono y en el borde
    // inferior real de la barra. Con edges/gravity verticales solamente,
    // PopupAnchor centra el popup en el eje horizontal.
    // +6 deja la cola casi tocando el filo de la barra, con un aire mínimo.
    anchor.rect.x: showArrow ? (anchorItem ? anchorItem.width / 2 : 0) : 0
    anchor.rect.y: showArrow ? barBottomInItem + 6 : 0
    anchor.rect.width: showArrow ? 1 : (anchorItem ? anchorItem.width : 1)
    anchor.rect.height: showArrow ? 1 : (anchorItem ? anchorItem.height : 1)

    implicitWidth: menuWidth + bleed * 2
    implicitHeight: topPad + (showArrow ? arrowH : 0) + body.height + bleed

    // El área transparente alrededor de la burbuja no debe capturar clics.
    mask: Region { item: body }

    onClosed: close()
    onOpenedChanged: {
        if (opened)
            Qt.callLater(updateArrow);
    }
    onXChanged: updateArrow()
    onWidthChanged: updateArrow()

    Connections {
        target: root.anchor
        function onAnchoring() {
            root.updateArrow();
        }
    }

    Connections {
        target: root.anchorItem
        function onXChanged() {
            root.updateArrow();
        }
        function onWidthChanged() {
            root.updateArrow();
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.opened
        onActivated: root.close()
    }

    QsMenuOpener {
        id: opener
        menu: root.menuHandle
    }

    Item {
        id: content
        anchors.fill: parent

        opacity: root.opened ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        // Hueco superior para la cola. El cuerpo empieza justo debajo.
        Item {
            id: body
            x: root.bleed
            y: root.topPad + (root.showArrow ? root.arrowH - 1 : 0)
            width: root.menuWidth

            readonly property int contentHeight: menuColumn.implicitHeight + 12
            height: Math.max(40, Math.min(contentHeight, root.maxMenuHeight))

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

            HoverHandler {
                id: bodyHover
                onHoveredChanged: root.menuHovered = hovered
            }

            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: body.contentHeight
                interactive: contentHeight > height

                Column {
                    id: menuColumn
                    x: 0
                    y: 6
                    width: flick.width

                    Repeater {
                        model: opener.children

                        delegate: Item {
                            id: entry
                            required property var modelData

                            readonly property bool separator: modelData ? modelData.isSeparator : false
                            readonly property bool entryEnabled: modelData ? modelData.enabled : false
                            readonly property bool hasChildren: modelData ? modelData.hasChildren : false
                            width: menuColumn.width
                            height: separator ? 6 : 40

                            // Sin líneas divisorias: el espaciado ya separa
                            // los grupos y evita el trazo que cruzaba el menú.
                            Rectangle {
                                visible: false
                                height: 1
                                color: Theme.m3OutlineVariant
                            }

                            Rectangle {
                                id: hoverPill
                                visible: !entry.separator
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 8
                                color: hover.hovered && entry.entryEnabled
                                    ? Theme.chipHover
                                    : "transparent"
                            }

                            RowLayout {
                                visible: !entry.separator
                                anchors.fill: parent
                                anchors {
                                    leftMargin: 14
                                    rightMargin: 12
                                }
                                spacing: 10

                                IconImage {
                                    visible: entry.modelData && entry.modelData.icon !== ""
                                    implicitSize: 16
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: entry.modelData ? entry.modelData.icon : ""
                                    opacity: entry.entryEnabled ? 1 : 0.5
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: entry.modelData ? entry.modelData.text : ""
                                    color: entry.entryEnabled
                                        ? Theme.m3OnSurface
                                        : Theme.m3OnSurfaceVariant
                                    opacity: entry.entryEnabled ? 1 : 0.5
                                    font.family: Theme.fontUI
                                    font.pixelSize: Theme.fontPx
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    visible: entry.hasChildren
                                        && entry.modelData
                                        && entry.modelData.text !== ""
                                    text: "›"
                                    color: Theme.m3OnSurfaceVariant
                                    font.family: Theme.fontUI
                                    font.pixelSize: 17
                                    Layout.preferredWidth: 12
                                    horizontalAlignment: Text.AlignRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            HoverHandler {
                                id: hover
                                enabled: !entry.separator && entry.entryEnabled
                                cursorShape: entry.entryEnabled
                                    ? Qt.PointingHandCursor
                                    : Qt.ArrowCursor
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !entry.separator && entry.entryEnabled
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (entry.hasChildren) {
                                        root.submenuRequested(entry.modelData, entry);
                                    } else {
                                        root.activateEntry(entry.modelData);
                                    }
                                }
                            }

                            Timer {
                                id: hoverTimer
                                interval: 160
                                onTriggered: {
                                    if (hover.hovered && entry.hasChildren)
                                        root.submenuRequested(entry.modelData, entry);
                                }
                            }

                            Connections {
                                target: hover
                                function onHoveredChanged() {
                                    if (!hover.hovered) {
                                        hoverTimer.stop();
                                        return;
                                    }

                                    // Al entrar en otra fila, el submenú anterior
                                    // debe desaparecer; si la fila es la dueña,
                                    // se deja abierto.
                                    if (root.childMenu
                                            && root.childMenu.anchorItem !== entry)
                                        root.childMenu.close();

                                    if (entry.hasChildren && entry.entryEnabled
                                            && (!root.childMenu
                                                || root.childMenu.anchorItem !== entry))
                                        hoverTimer.restart();
                                    else
                                        hoverTimer.stop();
                                }
                            }

                        }
                    }
                }
            }
        }

        // Cola superior: mismo relleno que la burbuja, sin borde.
        Shape {
            id: tail
            visible: root.showArrow
            x: Math.round(root.bleed + root.arrowCenter - root.arrowW / 2)
            y: 0
            width: root.arrowW
            height: root.arrowH + 1
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: bubble.color
                startX: 0
                startY: tail.height
                PathLine { x: tail.width / 2; y: 0 }
                PathLine { x: tail.width; y: tail.height }
                PathLine { x: 0; y: tail.height }
            }
        }
    }
}

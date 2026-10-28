import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"
import "../icons"
import "EmojiData.js" as EmojiData
import "InputMode.js" as InputMode

// Menú central de aplicaciones. La tarjeta vive en una capa overlay para que
// la búsqueda reciba el teclado sin pelearse con la barra ni con el dock.
PanelWindow {
    id: root

    required property var menuState
    property var clipboardHistory: null

    readonly property bool opened: menuState ? menuState.opened : false
    readonly property bool active: opened && menuState.activeScreen === screen
    property bool closing: false

    readonly property int animDuration: 220
    readonly property int cardWidth: Math.min(860,
        Math.max(640, Math.round((screen ? screen.width : 1920) * 0.60)))
    readonly property int cardHeight: Math.min(620,
        Math.max(460, Math.round((screen ? screen.height : 1080) * 0.62)))
    // Columna reservada para el rail (margen + barra). La barra mide
    // railWidth - 2 * railInset de ancho; baja railInset para pegarla más al
    // borde del menú o sube railWidth para hacerla más ancha.
    readonly property int railWidth: 60
    readonly property int railInset: 8
    // Icono de la distro (PikaOS). Se usa el primer nombre que exista en el
    // tema de iconos; si ninguno existe se queda el icono genérico.
    readonly property string distroIcon: root.findIcon([
        "distributor-logo-pikaos", "distributor-logo-pika-os",
        "pikaos", "pika-os", "pikaos-logo",
        "distributor-logo", "start-here"
    ])
    readonly property int contentWidth: root.cardWidth - root.railWidth - 40
    readonly property string mode: menuState ? menuState.mode : "apps"
    readonly property string category: menuState ? menuState.category : "all"

    property int appRevision: 0
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            // El escaneo de .desktop termina después de abrir el menú.
            root.appRevision += 1;
        }
    }
    readonly property var filteredApps: {
        // DesktopEntries se llena de forma asíncrona al arrancar; la
        // revisión fuerza una lectura nueva cada vez que se abre el menú.
        root.appRevision;
        const entries = DesktopEntries.applications
            ? DesktopEntries.applications.values
            : [];
        return root.filterApps(entries, root.category, searchInput.text);
    }
    readonly property var filteredEmojis: EmojiData.search(searchInput.text)
    readonly property var clipboardItems: root.clipboardHistory
        ? root.clipboardHistory.items
        : []
    readonly property var filteredClipboard: root.filterClipboard(
        root.clipboardItems, searchInput.text)

    readonly property int appColumns: Math.max(3,
        Math.floor(root.contentWidth / 150))
    readonly property int appCellWidth: Math.floor(root.contentWidth / root.appColumns)
    readonly property int appCellHeight: 108
    readonly property int emojiColumns: Math.max(4,
        Math.floor(root.contentWidth / 54))
    readonly property int emojiCellWidth: Math.floor(root.contentWidth / root.emojiColumns)
    readonly property int emojiCellHeight: 52

    readonly property var categories: [
        { key: "all",         icon: root.distroIcon || "applications-all",
          tint: root.distroIcon === "", label: "Todas" },
        { key: "development", icon: "applications-development", label: "Desarrollo" },
        { key: "graphics",    icon: "applications-graphics",    label: "Gráficos" },
        { key: "internet",    icon: "applications-internet",    label: "Internet" },
        { key: "multimedia",  icon: "applications-multimedia",  label: "Multimedia" },
        { key: "office",      icon: "applications-office",      label: "Oficina" },
        { key: "games",       icon: "applications-games",       label: "Juegos" },
        { key: "system",      icon: "applications-system",      label: "Sistema" },
        { key: "utilities",   icon: "applications-utilities",   label: "Utilidades" },
        { key: "other",       icon: "applications-other",       label: "Otras" }
    ]
    readonly property var modes: [
        { key: "emoji",     icon: "preferences-desktop-emoticons", label: "Emojis" },
        { key: "clipboard", icon: "xclipboard",                    label: "Portapapeles" }
    ]

    function findIcon(names) {
        for (let i = 0; i < names.length; ++i) {
            const path = IconResolver.resolved(names[i]);
            if (path && path.length > 0)
                return path;
        }
        return "";
    }

    function selectCategory(key) {
        if (!root.menuState)
            return;
        root.menuState.mode = "apps";
        root.menuState.category = key;
        searchInput.text = "";
        root.resetSelection();
        Qt.callLater(function() { searchInput.forceActiveFocus(); });
    }

    // Cursor único de la cuadrícula de apps. El teclado y el ratón ya no
    // llevan cada uno su propia posición: el estado (InputMode.js) recuerda
    // cuál de los dos lo manda, así que el último dispositivo usado toma el
    // control y el otro deja de robar la selección.
    property var selector: InputMode.initial()
    readonly property int selectedIndex: root.selector.cursor
    readonly property int appCount: root.filteredApps.length
    readonly property int safeIndex: Math.max(0,
        Math.min(root.selectedIndex, root.appCount - 1))

    function resetSelection() {
        root.selector = InputMode.transition(root.selector, { type: "reset" });
        appGrid.currentIndex = 0;
        appGrid.positionViewAtBeginning();
    }

    // El puntero se ha movido por el menú. El recorrido se acumula y sólo al
    // superar el umbral el ratón vuelve a mandar: el temblor del puntero no
    // roba la selección del teclado.
    function notePointerPosition(x, y) {
        root.selector = InputMode.transition(root.selector,
            { type: "pointer", x: x, y: y });
        root.syncGridCursor();
    }

    // El puntero ha entrado en una tarjeta: con el ratón mandando el cursor
    // pasa a ella, con el teclado mandando sólo se anota.
    function noteHover(index) {
        root.selector = InputMode.transition(root.selector,
            { type: "hover", index: index });
        root.syncGridCursor();
    }

    function noteHoverExit(index) {
        root.selector = InputMode.transition(root.selector,
            { type: "hoverExit", index: index });
    }

    // Escribir en el buscador devuelve el control al teclado.
    function noteTyping() {
        root.selector = InputMode.transition(root.selector, { type: "text" });
    }

    // Mantiene el currentIndex de la cuadrícula al día con el cursor.
    function syncGridCursor() {
        const index = root.safeIndex;
        if (appGrid.currentIndex !== index)
            appGrid.currentIndex = index;
    }

    // Mueve la selección con las flechas. El foco se queda en el buscador
    // para poder seguir escribiendo.
    function moveAppSelection(direction) {
        const count = root.appCount;
        if (count === 0)
            return;
        const columns = Math.max(1,
            Math.floor(appGrid.width / Math.max(1, appGrid.cellWidth)));
        root.selector = InputMode.transition(root.selector, {
            type: "move",
            direction: direction,
            columns: columns,
            count: count
        });
        const index = root.safeIndex;
        appGrid.currentIndex = index;
        appGrid.positionViewAtIndex(index, GridView.Contain);
    }

    // Enter en el buscador: lanza la app seleccionada (o la emoji/entrada
    // de portapapeles que corresponda al modo).
    function activateSelection() {
        if (root.mode === "apps") {
            const entry = root.filteredApps[root.safeIndex];
            if (entry)
                root.launchEntry(entry);
        } else if (root.mode === "emoji" && root.filteredEmojis.length > 0) {
            root.insertEmoji(root.filteredEmojis[0].char);
        } else if (root.mode === "clipboard" && root.filteredClipboard.length > 0) {
            root.copyClipboard(root.filteredClipboard[0].text);
        }
    }

    function selectMode(nextMode) {
        if (!root.menuState)
            return;
        root.menuState.mode = nextMode;
        if (nextMode === "apps")
            root.menuState.category = "all";
        searchInput.text = "";
        Qt.callLater(function() { searchInput.forceActiveFocus(); });
    }

    function close() {
        if (root.menuState)
            root.menuState.close();
    }

    function launchEntry(entry) {
        if (!entry)
            return;
        root.close();
        if (typeof entry.execute === "function")
            entry.execute();
        else if (entry.id)
            Quickshell.execDetached(["gio", "launch", String(entry.id)]);
    }

    function insertEmoji(emoji) {
        if (!emoji)
            return;
        // wtype no puede mapear emojis a un keysym, así que se deja el emoji
        // en el portapapeles y se pega en la ventana que recupera el foco.
        Quickshell.clipboardText = emoji;
        root.close();
        pasteTimer.restart();
    }

    function copyClipboard(text) {
        if (text === undefined || text === null)
            return;
        Quickshell.clipboardText = String(text);
        root.close();
    }

    function clearClipboard() {
        if (root.clipboardHistory
                && typeof root.clipboardHistory.clear === "function")
            root.clipboardHistory.clear();
    }

    function filterApps(entries, filter, query) {
        const list = entries && typeof entries.length === "number" ? entries : [];
        const q = String(query || "").trim().toLowerCase();
        const result = [];

        for (let i = 0; i < list.length; ++i) {
            const entry = list[i];
            if (!entry || entry.noDisplay)
                continue;
            if (!root.categoryMatches(entry, filter))
                continue;
            if (q) {
                const haystack = (String(entry.name || "") + " "
                    + String(entry.genericName || "") + " "
                    + String(entry.comment || "") + " "
                    + String(entry.id || "") + " "
                    + String(entry.keywords || "")).toLowerCase();
                if (haystack.indexOf(q) === -1)
                    continue;
            }
            result.push(entry);
        }

        // Varias fuentes exponen el mismo .desktop (Flatpak del sistema y del
        // usuario, AppImage con dos IDs, restos de KDE4) con distinto id o
        // comando, así que la identidad real es el nombre visible. Se
        // conserva la primera entrada de cada nombre.
        const unique = [];
        const seen = Object.create(null);
        for (let i = 0; i < result.length; ++i) {
            const entry = result[i];
            const key = String(entry.name || "").trim().toLowerCase();
            if (!key || seen[key])
                continue;
            seen[key] = true;
            unique.push(entry);
        }

        unique.sort(function(a, b) {
            const left = String(a.name || "").toLowerCase();
            const right = String(b.name || "").toLowerCase();
            return left < right ? -1 : (left > right ? 1 : 0);
        });
        return unique;
    }

    // Categorías de freedesktop (en minúsculas) que cuentan para cada pestaña.
    // Los .desktop reales usan muchas subcategorías sin la principal (p. ej.
    // "Audio;Player", "Settings", "Emulator"), así que no basta con la principal.
    readonly property var categoryAliases: ({
        development: ["development", "ide", "debugger", "webdevelopment",
            "building", "guidesigner", "revisioncontrol", "profiling",
            "translation", "database"],
        graphics: ["graphics", "2dgraphics", "3dgraphics", "rastergraphics",
            "vectorgraphics", "photography", "scanning", "ocr"],
        internet: ["network", "webbrowser", "email", "instantmessaging", "chat",
            "ircclient", "filetransfer", "p2p", "remoteaccess", "telephony",
            "videoconference", "news", "feed"],
        multimedia: ["audiovideo", "audio", "video", "music", "player",
            "recorder", "midi", "mixer", "sequencer", "tuner", "tv",
            "audiovideoediting", "discburning"],
        office: ["office", "wordprocessor", "spreadsheet", "presentation",
            "calendar", "contactmanagement", "projectmanagement", "finance",
            "publishing", "dictionary"],
        games: ["game", "emulator", "roleplaying", "shooter"],
        system: ["system", "settings", "desktopsettings", "hardwaresettings",
            "packagemanager", "monitor", "terminalemulator", "filemanager",
            "filesystem", "security", "printing"],
        utilities: ["utility", "texteditor", "archiving", "compression",
            "calculator", "clock", "accessibility", "texttools", "filetools"]
    })

    // Categorías del .desktop como lista de minúsculas, sea cual sea la forma
    // en que Quickshell las entregue (lista, secuencia de Qt o texto "A;B;").
    function categoryValues(entry) {
        const raw = entry ? entry.categories : null;
        const values = [];
        if (raw === null || raw === undefined)
            return values;
        if (typeof raw === "string") {
            const parts = raw.split(/[;,]/);
            for (let i = 0; i < parts.length; ++i) {
                const value = parts[i].trim().toLowerCase();
                if (value !== "")
                    values.push(value);
            }
        } else if (typeof raw.length === "number") {
            for (let i = 0; i < raw.length; ++i) {
                const value = String(raw[i]).trim().toLowerCase();
                if (value !== "")
                    values.push(value);
            }
        }
        return values;
    }

    function matchesKey(values, key) {
        const aliases = root.categoryAliases[key];
        if (!aliases)
            return false;
        for (let i = 0; i < values.length; ++i) {
            const value = values[i];
            if (aliases.indexOf(value) !== -1)
                return true;
            // ActionGame, BoardGame, StrategyGame...
            if (key === "games" && value.length > 4
                    && value.slice(-4) === "game")
                return true;
        }
        return false;
    }

    function categoryMatches(entry, filter) {
        if (filter === "all")
            return true;

        const values = root.categoryValues(entry);
        // "Otras": lo que no cae en ninguna de las demás pestañas (incluye
        // educación, ciencia y apps sin categoría reconocible).
        if (filter === "other") {
            const keys = Object.keys(root.categoryAliases);
            for (let i = 0; i < keys.length; ++i) {
                if (root.matchesKey(values, keys[i]))
                    return false;
            }
            return true;
        }
        return root.matchesKey(values, filter);
    }

    function filterClipboard(items, query) {
        const list = items && typeof items.length === "number" ? items : [];
        const q = String(query || "").trim().toLowerCase();
        if (!q)
            return list;
        const result = [];
        for (let i = 0; i < list.length; ++i) {
            const item = list[i];
            if (item && String(item.text || "").toLowerCase().indexOf(q) !== -1)
                result.push(item);
        }
        return result;
    }

    function preview(value) {
        const text = String(value || "").replace(/\s+/g, " ").trim();
        return text.length > 0 ? text : "…";
    }

    function formatTime(value) {
        const date = new Date(Number(value || 0) * 1000);
        if (isNaN(date.getTime()))
            return "";
        return Qt.formatTime(date, "hh:mm");
    }

    visible: root.opened || root.closing
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: root.active
    color: "transparent"
    BackgroundEffect.blurRegion: Region {
        // Sólo se difumina bajo la tarjeta del monitor activo; en el otro
        // monitor la tarjeta es invisible y no debe dejar un parche borroso.
        item: root.active ? cardBounds : null
        radius: 24
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.active
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    onOpenedChanged: {
        if (root.opened) {
            root.closing = false;
            closeTimer.stop();
            searchInput.text = "";
            root.resetSelection();
            root.selector = InputMode.transition(root.selector, { type: "open" });
            emojiGrid.currentIndex = 0;
            root.appRevision += 1;
            Qt.callLater(function() {
                if (root.active)
                    searchInput.forceActiveFocus();
            });
        } else {
            root.closing = true;
            root.selector = InputMode.initial();
            closeTimer.restart();
        }
    }

    Component.onCompleted: {
        if (root.opened) {
            searchInput.text = "";
            root.appRevision += 1;
            Qt.callLater(function() {
                if (root.active)
                    searchInput.forceActiveFocus();
            });
        }
    }

    Timer {
        id: closeTimer
        interval: root.animDuration + 20
        onTriggered: {
            root.closing = false;
            if (root.menuState
                    && typeof root.menuState.finishClose === "function")
                root.menuState.finishClose();
        }
    }

    Timer {
        id: pasteTimer
        interval: 280
        onTriggered: {
            // KWin no expone el protocolo de teclado virtual que usa wtype.
            // ydotool inyecta la tecla por uinput; si tampoco está disponible,
            // el emoji queda en el portapapeles para pegarlo a mano.
            Quickshell.execDetached([
                "bash", "-lc",
                "wtype -M ctrl -k v -m ctrl 2>/dev/null"
                    + " || ydotool key 29:1 47:1 47:0 29:0"
            ]);
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.active
        onActivated: root.close()
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "#000000"
        opacity: root.opened ? 0.20 : 0

        Behavior on opacity {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.close()
    }

    Item {
        id: card
        anchors.centerIn: parent
        width: root.cardWidth
        height: root.cardHeight
        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 0.96
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.animDuration
                easing.type: Easing.OutBack
                easing.overshoot: 1.03
            }
        }

        transform: Translate {
            y: root.active ? 0 : 14
            Behavior on y {
                NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic }
            }
        }

        // Marca la geometría de la tarjeta para la región de blur (cardSurface
        // está oculta porque la dibuja el MultiEffect).
        Item {
            id: cardBounds
            anchors.fill: parent
        }

        MultiEffect {
            id: cardFx
            source: cardSurface
            anchors.fill: cardSurface
            // Sombra amplia y suave: el desenfoque grande evita el borde duro,
            // el desplazamiento vertical la "levanta" y la escala algo menor
            // que 1 impide que asome como un marco alrededor de la tarjeta.
            blurMax: 64
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.38
            shadowBlur: 0.85
            shadowScale: 0.97
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 16
        }

        Rectangle {
            id: cardSurface
            anchors.fill: parent
            radius: 24
            color: Theme.surface
            border.width: 1
            border.color: Theme.m3OutlineVariant
            // La dibuja el MultiEffect; ocultarla evita dibujarla dos veces
            // y que quede un halo en las esquinas.
            visible: false
        }

        // Evita que un clic en el fondo de la tarjeta cierre el menú.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        Rectangle {
            id: rail
            x: root.railInset
            y: root.railInset
            width: root.railWidth - 2 * root.railInset
            height: parent.height - 2 * root.railInset
            radius: 18
            color: Theme.m3SurfaceContainerLow

            Column {
                id: categoryColumn
                anchors {
                    top: parent.top
                    topMargin: 12
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 3

                Repeater {
                    model: root.categories
                    delegate: RailButton {
                        icon: modelData.icon
                        tint: modelData.tint !== false
                        selected: root.mode === "apps"
                            && root.category === modelData.key
                        onActivated: root.selectCategory(modelData.key)
                    }
                }
            }

            Column {
                id: modeColumn
                anchors {
                    bottom: parent.bottom
                    bottomMargin: 12
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 3

                Repeater {
                    model: root.modes
                    delegate: RailButton {
                        icon: modelData.icon
                        selected: root.mode === modelData.key
                        onActivated: root.selectMode(modelData.key)
                    }
                }
            }
        }

        Item {
            id: contentArea
            anchors {
                left: rail.right
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                leftMargin: 20 + root.railInset
                rightMargin: 20
                topMargin: 18
                bottomMargin: 18
            }

            Rectangle {
                id: searchBox
                width: parent.width
                height: 46
                radius: height / 2
                color: Theme.chip
                border.width: searchInput.activeFocus ? 1 : 0
                border.color: Theme.m3Primary

                Item {
                    id: searchIcon
                    x: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18

                    IconImage {
                        anchors.fill: parent
                        source: IconResolver.firstOf(["edit-find", "system-search", "edit-find-symbolic"])
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: Theme.textDim
                        }
                    }
                }

                TextInput {
                    id: searchInput
                    anchors {
                        left: searchIcon.right
                        right: clearButton.left
                        leftMargin: 10
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    height: 30
                    clip: true
                    color: Theme.text
                    selectionColor: Theme.m3Primary
                    selectedTextColor: Theme.m3OnPrimary
                    font.family: Theme.fontUI
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    verticalAlignment: TextInput.AlignVCenter

                    onTextChanged: {
                        root.resetSelection();
                        emojiGrid.currentIndex = 0;
                    }

                    onTextEdited: root.noteTyping()

                    Keys.onEscapePressed: root.close()
                    // Flechas: en apps mueven la selección sin quitar el foco al
                    // buscador; en emoji y portapapeles pasan el foco a su lista.
                    Keys.onDownPressed: {
                        if (root.mode === "apps")
                            root.moveAppSelection("down");
                        else if (root.mode === "emoji")
                            emojiGrid.forceActiveFocus();
                        else
                            clipboardList.forceActiveFocus();
                    }
                    Keys.onUpPressed: function(event) {
                        if (root.mode === "apps")
                            root.moveAppSelection("up");
                        else
                            event.accepted = false;
                    }
                    Keys.onLeftPressed: function(event) {
                        if (root.mode === "apps" && root.filteredApps.length > 0)
                            root.moveAppSelection("left");
                        else
                            event.accepted = false;
                    }
                    Keys.onRightPressed: function(event) {
                        if (root.mode === "apps" && root.filteredApps.length > 0)
                            root.moveAppSelection("right");
                        else
                            event.accepted = false;
                    }
                    Keys.onReturnPressed: root.activateSelection()
                    Keys.onEnterPressed: root.activateSelection()
                }

                Text {
                    id: placeholder
                    anchors {
                        left: searchInput.left
                        right: searchInput.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.mode === "emoji"
                        ? "Buscar emojis…"
                        : root.mode === "clipboard"
                            ? "Buscar en el portapapeles…"
                            : "Buscar aplicaciones…"
                    color: Theme.textDim
                    font: searchInput.font
                    elide: Text.ElideRight
                    visible: searchInput.text.length === 0
                }

                Item {
                    id: clearButton
                    anchors {
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    width: searchInput.text.length > 0 ? 26 : 0
                    height: 26
                    opacity: width > 0 ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 13
                        color: clearHover.hovered ? Theme.chipHover : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: clearHover.hovered ? Theme.text : Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 18
                    }

                    HoverHandler {
                        id: clearHover
                        enabled: clearButton.width > 0
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: clearButton.width > 0
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = "";
                            searchInput.forceActiveFocus();
                        }
                    }
                }
            }

            Item {
                id: body
                anchors {
                    top: searchBox.bottom
                    topMargin: 16
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                clip: true

                // Recorrido del puntero por el cuerpo del menú. Se mide en
                // coordenadas de esta área, así que no salta cuando la lista
                // se desplaza con el teclado bajo un cursor quieto.
                HoverHandler {
                    onPointChanged: root.notePointerPosition(
                        point.position.x, point.position.y)
                }

                GridView {
                    id: appGrid
                    anchors.fill: parent
                    visible: root.mode === "apps"
                    model: root.filteredApps
                    reuseItems: false
                    cellWidth: root.appCellWidth
                    cellHeight: root.appCellHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationWraps: true

                    delegate: Item {
                        width: appGrid.cellWidth
                        height: appGrid.cellHeight

                        AppTile {
                            anchors.centerIn: parent
                            width: Math.min(156, parent.width - 8)
                            entry: modelData
                            selected: root.safeIndex === index
                            onActivated: root.launchEntry(modelData)
                            onHoverEntered: root.noteHover(index)
                            onHoverExited: root.noteHoverExit(index)
                        }
                    }

                    Keys.onEscapePressed: root.close()
                    Keys.onReturnPressed: {
                        const entry = appGrid.model[appGrid.currentIndex];
                        if (entry)
                            root.launchEntry(entry);
                    }
                }

                GridView {
                    id: emojiGrid
                    anchors.fill: parent
                    visible: root.mode === "emoji"
                    model: root.filteredEmojis
                    cellWidth: root.emojiCellWidth
                    cellHeight: root.emojiCellHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationWraps: true

                    delegate: Item {
                        width: emojiGrid.cellWidth
                        height: emojiGrid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 12
                            color: emojiHover.hovered ? Theme.chipHover : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.durFast
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.char
                            font.family: "Noto Color Emoji"
                            font.pixelSize: 26
                        }

                        HoverHandler {
                            id: emojiHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.insertEmoji(modelData.char)
                        }
                    }

                    Keys.onEscapePressed: root.close()
                    Keys.onReturnPressed: {
                        const emoji = emojiGrid.model[emojiGrid.currentIndex];
                        if (emoji)
                            root.insertEmoji(emoji.char);
                    }
                }

                Item {
                    id: clipboardView
                    anchors.fill: parent
                    visible: root.mode === "clipboard"

                    Item {
                        id: clipboardHeader
                        width: parent.width
                        height: 28

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Portapapeles"
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Item {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            width: 54
                            height: 26
                            visible: root.clipboardItems.length > 0

                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: clearHistoryHover.hovered
                                    ? Theme.chipHover
                                    : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "Limpiar"
                                color: clearHistoryHover.hovered
                                    ? Theme.m3Primary
                                    : Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }

                            HoverHandler {
                                id: clearHistoryHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearClipboard()
                            }
                        }
                    }

                    ListView {
                        id: clipboardList
                        anchors {
                            top: clipboardHeader.bottom
                            topMargin: 4
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        model: root.filteredClipboard
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            width: clipboardList.width
                            height: 56

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: clipHover.hovered ? Theme.chipHover : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Theme.durFast
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            Column {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: 14
                                    rightMargin: 14
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: root.preview(modelData.text)
                                    color: Theme.text
                                    font.family: Theme.fontUI
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Text {
                                    text: root.formatTime(modelData.ts)
                                    color: Theme.textDim
                                    font.family: Theme.fontUI
                                    font.pixelSize: 10
                                }
                            }

                            HoverHandler {
                                id: clipHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.copyClipboard(modelData.text)
                            }
                        }

                        Keys.onEscapePressed: root.close()
                        Keys.onReturnPressed: {
                            const item = clipboardList.model[clipboardList.currentIndex];
                            if (item)
                                root.copyClipboard(item.text);
                        }
                    }

                    Text {
                        visible: root.filteredClipboard.length === 0
                        anchors.centerIn: parent
                        text: searchInput.text.length > 0
                            ? "No hay coincidencias"
                            : "El historial está vacío"
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: 13
                    }
                }

                Text {
                    visible: root.mode === "apps" && root.filteredApps.length === 0
                    anchors.centerIn: parent
                    text: "No hay aplicaciones"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 13
                }

                Text {
                    visible: root.mode === "emoji" && root.filteredEmojis.length === 0
                    anchors.centerIn: parent
                    text: "No hay emojis"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 13
                }
            }
        }
    }
}

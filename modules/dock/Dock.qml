import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../../theme"
import "../icons"
import "DockEntries.js" as DockEntries
import "DockSmartHide.js" as DockSmartHide

PanelWindow {
    id: dock

    required property var modelData
    property string activeAppId: ""
    property var windowAppIds: []
    property var trayMenuState: null
    property var secondMenuState: null

    // Abre el menú secundario directamente en la categoría Música (o lo
    // cierra si ya estaba abierto en esa misma categoría).
    function openMusicMenu() {
        if (!dock.secondMenuState)
            return;
        if (dock.secondMenuState.opened
                && dock.secondMenuState.category === "musica") {
            dock.secondMenuState.close();
            return;
        }
        dock.secondMenuState.open(dock.screen, "musica");
    }

    // Arranque de fábrica. El estado real vive en ~/.config/caparazon/dock.json
    // y esta lista sólo se usa cuando ese archivo todavía no existe.
    readonly property var defaultPinnedApps: [
        {
            key: "zen",
            name: "Zen Browser",
            entryId: "app.zen_browser.zen.desktop",
            icon: "app.zen_browser.zen",
            matches: ["app.zen_browser.zen", "zen"],
            command: ["flatpak", "run", "app.zen_browser.zen"],
            newCommand: ["flatpak", "run", "app.zen_browser.zen", "--blank-window"],
            pinned: true
        },
        {
            key: "steam",
            name: "Steam",
            entryId: "steam.desktop",
            icon: "steam",
            matches: ["steam"],
            command: ["steam"],
            newCommand: ["steam"],
            pinned: true
        },
        {
            key: "dolphin",
            name: "Dolphin",
            entryId: "org.kde.dolphin.desktop",
            icon: "org.kde.dolphin",
            matches: ["org.kde.dolphin", "dolphin"],
            command: ["dolphin"],
            newCommand: ["dolphin"],
            pinned: true
        },
        {
            key: "limusic",
            name: "limusic",
            entryId: "limusic.desktop",
            icon: "limusic-app",
            matches: ["limusic", "limusic-app"],
            command: ["limusic-app"],
            newCommand: ["limusic-app"],
            pinned: true
        },
        {
            key: "waydroid",
            name: "Waydroid",
            entryId: "Waydroid.desktop",
            icon: "waydroid",
            matches: ["waydroid"],
            command: ["waydroid", "first-launch"],
            newCommand: ["waydroid", "first-launch"],
            pinned: true
        }
    ]

    readonly property string configHome: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        return (xdg && xdg.length > 0) ? xdg : Quickshell.env("HOME") + "/.config";
    }
    readonly property string pinsPath: configHome + "/caparazon/dock.json"

    FileView {
        id: pinsFile
        path: dock.pinsPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: pinsAdapter
            property var pinned: dock.defaultPinnedApps
            property bool dockPinned: false
        }
    }

    // Cuando Quickshell termina de escanear los .desktop (o se instala uno
    // nuevo mientras la shell está activa), las búsquedas en caché pueden
    // haberse quedado vacías: se borran para que se resuelvan de nuevo.
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            dock.appEntryCache = {};
        }
    }

    readonly property var pinnedApps: pinsAdapter.pinned || []
    property var appEntryCache: ({})

    // Apps con ventanas abiertas que no están ancladas. Se agrupan por
    // appId para que varias ventanas de la misma app ocupen un solo icono.
    readonly property var runningApps: {
        const ids = dock.windowAppIds || [];
        const seen = ({});
        const result = [];

        for (let i = 0; i < ids.length; ++i) {
            const raw = String(ids[i] || "");
            const id = normalizeId(raw);
            if (!id || seen[id])
                continue;

            let isPinned = false;
            for (let j = 0; j < dock.pinnedApps.length; ++j) {
                if (matchesApp(dock.pinnedApps[j], raw)) {
                    isPinned = true;
                    break;
                }
            }
            if (isPinned)
                continue;

            const entry = desktopEntryForAppId(raw);
            seen[id] = true;
            result.push({
                key: "running:" + id,
                name: entry && entry.name ? entry.name : displayName(raw),
                entryId: entry ? entry.id + ".desktop" : id + ".desktop",
                icon: entry && entry.icon ? entry.icon : raw,
                iconCandidates: DockEntries.iconCandidates(entry, raw),
                focusId: id,
                matches: [raw],
                command: [],
                newCommand: [],
                pinned: false
            });
        }

        return result;
    }

    readonly property var dockApps: dock.pinnedApps.concat(dock.runningApps)

    Process {
        id: windowActionProcess
        running: false
        property string target: ""
        property string active: ""

        command: [
            "bash", "-c",
            "target=\"$1\"; active=\"$2\"; " +
            "case \"$target\" in ''|*[!A-Za-z0-9._|-]*) exit 1;; esac; " +
            "case \"$active\" in *[!A-Za-z0-9._-]*) active='';; esac; " +
            "tmp=\"${XDG_RUNTIME_DIR:-/tmp}/caparazon-window-action-$$.js\"; " +
            "sed -e \"s@__TARGET__@$target@g\" -e \"s@__ACTIVE__@$active@g\" \"$3\" > \"$tmp\"; " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting " +
            "--method org.kde.kwin.Scripting.unloadScript caparazon-window-action >/dev/null 2>&1; " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting " +
            "--method org.kde.kwin.Scripting.loadScript \"$tmp\" caparazon-window-action >/dev/null; " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting " +
            "--method org.kde.kwin.Scripting.start >/dev/null; " +
            "rm -f \"$tmp\"",
            "bash",
            windowActionProcess.target,
            windowActionProcess.active,
            Quickshell.shellPath("modules/bar/KWinWindowAction.js")
        ]
    }

    // Largo del contenido por su eje: la fila de siempre o la columna nueva.
    readonly property int contentLength: dock.vertical
        ? dockColumn.implicitHeight
        : dockRow.implicitWidth

    // En columna, el contenido sin los botones desplegados: el cristal se
    // calcula con esto para que su borde superior no se mueva al desplegar (si
    // se moviera, el puntero perdería la carátula y el despliegue parpadearía).
    readonly property int restContent: dock.vertical
        ? dockColumn.implicitHeight - musicTile.height + musicTile.cardHeight
        : 0
    readonly property int collapsedLength: Math.max(308,
        dock.restContent + 2 * Theme.padH + 16)

    readonly property int targetWidth: Math.max(
        dock.vertical
            ? dock.collapsedLength + (dock.contentLength - dock.restContent)
            : 308,
        dock.contentLength + 2 * Theme.padH + 16)
    property int dockWidth: 308

    // Al cambiar el contenido, el dock se pasa un poco del ancho objetivo
    // y vuelve a su tamaño final con un rebote corto.
    property bool widthReady: false

    SequentialAnimation {
        id: widthBounce

        NumberAnimation {
            id: widthBounceOut
            target: dock
            property: "dockWidth"
            duration: 130
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: widthBounceBack
            target: dock
            property: "dockWidth"
            duration: 190
            easing.type: Easing.OutCubic
        }
    }

    onTargetWidthChanged: {
        if (!widthReady) {
            dockWidth = targetWidth;
            return;
        }
        if (dock.deployAnimating) {
            // El contenido ya viene animado: seguirlo tal cual.
            widthBounce.stop();
            dockWidth = targetWidth;
            return;
        }
        animateDockWidth(targetWidth);
    }
    readonly property int bottomGap: 0

    // Borde al que se pega el dock: "bottom" (por defecto), "top", "left"
    // o "right". Con los laterales el dock pasa a columna vertical y tanto el
    // escondite como el borde caliente, la sombra y la forma giran 90°.
    property string position: "bottom"
    readonly property bool atTop: dock.position === "top"
    readonly property bool atBottom: dock.position === "bottom"
    readonly property bool atLeft: dock.position === "left"
    readonly property bool atRight: dock.position === "right"
    readonly property bool vertical: dock.atLeft || dock.atRight

    // El puntero está sobre el dock o sobre su franja sensible.
    property bool pointerOnDock: false

    readonly property bool dockPinned: pinsAdapter.dockPinned === true

    // Con un menú abierto el dock no se esconde, aunque el ratón salga de él.
    readonly property bool menuOpen: appMenu.opened || dock.trayMenuState > 0 || secondMenuState.opened

    // En columna la tarjeta del reproductor se estira al pasar el puntero y
    // vuelve a su sitio al salir: el despliegue va dentro del cristal, así que
    // no hay hueco que cruzar ni hace falta temporizador de gracia.
    readonly property bool musicExpanded: dock.vertical && musicTile.hovering

    // Mientras se despliega el largo del cristal sigue al contenido sin rebote:
    // el rebote se reiniciaría en cada fotograma y se vería tembloroso.
    property bool deployAnimating: false

    onMusicExpandedChanged: {
        dock.deployAnimating = true;
        deploySettle.restart();
    }

    Timer {
        id: deploySettle
        interval: 420
        onTriggered: dock.deployAnimating = false
    }

    // Al cerrar el menú el ratón ya no está sobre el dock: sin esta pauta
    // quedaba revelado para siempre, así que se rearranca la gracia.
    onMenuOpenChanged: {
        if (!menuOpen && !pointerOnDock)
            hideGrace.restart();
    }

    readonly property string smartState: DockSmartHide.stateFor(dock.dockPinned, dock.pointerOnDock)

    // Medidas que usa la librería de estados.
    readonly property var metrics: ({
        surfaceWidth: dock.width,
        surfaceHeight: dock.height,
        // Largo a lo largo del borde y grosor hacia dentro: la librería ya
        // razona en estos términos para los cuatro bordes.
        dockLength: dock.dockWidth,
        dockThickness: Theme.dockHeight,
        shadowPad: Theme.shadowPad,
        hotEdge: Theme.dockHotEdge,
        bottomGap: dock.bottomGap,
        position: dock.position
    })

    // Horizontal: la ventana cruza toda la pantalla y sólo ocupa el grosor.
    // Vertical: al revés, ocupa el grosor de ancho y cruza toda la altura.
    anchors {
        top: dock.atTop || dock.vertical
        bottom: dock.atBottom || dock.vertical
        left: dock.atLeft || !dock.vertical
        right: dock.atRight || !dock.vertical
    }

    margins {
        top: dock.atTop ? dock.bottomGap : 0
        bottom: dock.atBottom ? dock.bottomGap : 0
        left: dock.atLeft ? dock.bottomGap : 0
        right: dock.atRight ? dock.bottomGap : 0
    }

    implicitWidth: Theme.dockHeight + Theme.shadowPad
    implicitHeight: Theme.dockHeight + Theme.shadowPad
    exclusiveZone: DockSmartHide.exclusiveZone(dock.dockPinned, dock.metrics)
    color: "transparent"

    mask: Region { item: hitArea }


    Item {
        id: hitArea
        readonly property var rect: DockSmartHide.maskRect(dock.smartState, dock.metrics)
        x: rect.x
        y: rect.y
        width: rect.width
        height: rect.height
    }

    // El ratón al borde inferior devuelve el dock y, mientras esté encima,
    // lo mantiene revelado. El handler vive en la raíz de la ventana y no
    // dentro de hitArea porque es pasivo: los MouseArea de los iconos de
    // apps y de los botones multimedia se quedan con el hover, y un handler
    // hermano de hitArea dejaría de verlo y escondería el dock en pleno uso.
    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hideGrace.stop();
                dock.pointerOnDock = true;
            } else {
                if (!dock.menuOpen) {
                    hideGrace.restart();
                }
            }
        }
    }

    // Margen antes de volver a apartar el dock: si el ratón va hacia la
    // barra, no debe esconderse por el camino.
    Timer {
        id: hideGrace
        interval: Theme.dockHideGrace
        onTriggered: if (!dock.menuOpen) dock.pointerOnDock = false
    }

    DockMenu {
        id: appMenu
        menuState: dock.trayMenuState

        onPinRequested: dock.pinApp(appMenu.app)
        onUnpinRequested: dock.unpinApp(appMenu.app)
        onNewWindowRequested: dock.launch(appMenu.app, true)
    }

    property real reveal: 0
    Component.onCompleted: {
        widthReady = true;
        dockWidth = targetWidth;
        reveal = 1;
    }

    Behavior on reveal {
        NumberAnimation { duration: 460; easing.type: Easing.OutCubic }
    }

    Item {
        id: frame
        readonly property int thickness: Theme.dockHeight + Theme.shadowPad
        readonly property int hideOffset:
            DockSmartHide.dockOffset(dock.smartState, dock.metrics)

        // Horizontal: centrado a lo ancho y pegado al filo superior o inferior.
        // Vertical: centrado a lo alto y el grosor crece desde el filo lateral.
        x: dock.vertical
            ? (dock.atLeft
                ? -hideOffset
                : parent.width - width + hideOffset)
            : Math.round((parent.width - width) / 2)
        // En columna el alto crece con el despliegue: el borde superior se
        // ancla al largo plegado para que la carátula no se mueva.
        y: dock.vertical
            ? Math.round((parent.height
                - (dock.collapsedLength + 2 * Theme.shadowPad)) / 2)
            : (dock.atTop ? -hideOffset : parent.height - height + hideOffset)
        width: dock.vertical
            ? dock.reveal * thickness
            : dock.dockWidth + 2 * Theme.shadowPad
        height: dock.vertical
            ? dock.dockWidth + 2 * Theme.shadowPad
            : dock.reveal * thickness
        clip: true
        opacity: dock.smartState === "hidden" ? 0 : (0.25 + 0.75 * dock.reveal)

        Behavior on x {
            NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic }
        }

        Behavior on y {
            NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic }
        }

        MultiEffect {
            id: elevation
            source: glass
            x: glass.x
            y: glass.y
            width: glass.width
            height: glass.height

            blurMax: 32
            shadowEnabled: true
            shadowColor: Theme.shadowColor
            shadowOpacity: Theme.shadowOpacity
            shadowBlur: Theme.shadowBlur
            // La sombra cae siempre hacia dentro: hacia arriba con el dock
            // abajo, hacia abajo arriba y hacia dentro en los laterales.
            shadowHorizontalOffset: dock.atLeft
                ? Theme.shadowOffsetY
                : (dock.atRight ? -Theme.shadowOffsetY : 0)
            shadowVerticalOffset: dock.atTop
                ? Theme.shadowOffsetY
                : (dock.atBottom ? -Theme.shadowOffsetY : 0)
        }

        Shape {
            id: glass
            // El cristal ocupa el mismo rectángulo que el contenido; el
            // trazado se lleva al borde elegido mapeando sus puntos.
            x: contentClip.x
            y: contentClip.y
            width: contentClip.width
            height: contentClip.height
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                id: glassPath
                readonly property int rt: Theme.radius
                readonly property int rb: Theme.radiusTop
                // Largo y grosor en el espacio del trazado (filo abajo).
                readonly property real len: dock.vertical ? glass.height : glass.width
                readonly property real thick: dock.vertical ? glass.width : glass.height

                // El trazado se dibuja siempre con el filo abajo y el labio
                // cóncavo. Llevarlo al borde pedido es mapear cada punto:
                // arriba es un espejo (invierte los arcos), a los lados un
                // giro de 90° que conserva su sentido de recorrido.
                function px(x, y) {
                    if (dock.atLeft)
                        return glassPath.thick - y;
                    if (dock.atRight)
                        return y;
                    return x;
                }
                function py(x, y) {
                    if (dock.atLeft)
                        return x;
                    if (dock.atRight)
                        return glassPath.len - x;
                    if (dock.atTop)
                        return glassPath.thick - y;
                    return y;
                }
                function inverse(value) {
                    if (!dock.atTop)
                        return value;
                    return value === PathArc.Clockwise
                        ? PathArc.Counterclockwise : PathArc.Clockwise;
                }

                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Theme.surface

                // Borde del filo intacto: el cuerpo se abre hacia el borde.
                // Solo los dos arcos del filo curvan hacia adentro.
                startX: glassPath.px(0, glassPath.thick)
                startY: glassPath.py(0, glassPath.thick)

                PathLine {
                    x: glassPath.px(glassPath.len, glassPath.thick)
                    y: glassPath.py(glassPath.len, glassPath.thick)
                }

                PathArc {
                    x: glassPath.px(glassPath.len - glassPath.rb, glassPath.thick - glassPath.rb)
                    y: glassPath.py(glassPath.len - glassPath.rb, glassPath.thick - glassPath.rb)
                    radiusX: glassPath.rb
                    radiusY: glassPath.rb
                    direction: glassPath.inverse(PathArc.Clockwise)
                    useLargeArc: false
                }

                PathLine {
                    x: glassPath.px(glassPath.len - glassPath.rb, glassPath.rt)
                    y: glassPath.py(glassPath.len - glassPath.rb, glassPath.rt)
                }

                PathArc {
                    x: glassPath.px(glassPath.len - glassPath.rb - glassPath.rt, 0)
                    y: glassPath.py(glassPath.len - glassPath.rb - glassPath.rt, 0)
                    radiusX: glassPath.rt
                    radiusY: glassPath.rt
                    direction: glassPath.inverse(PathArc.Counterclockwise)
                    useLargeArc: false
                }

                PathLine {
                    x: glassPath.px(glassPath.rb + glassPath.rt, 0)
                    y: glassPath.py(glassPath.rb + glassPath.rt, 0)
                }

                PathArc {
                    x: glassPath.px(glassPath.rb, glassPath.rt)
                    y: glassPath.py(glassPath.rb, glassPath.rt)
                    radiusX: glassPath.rt
                    radiusY: glassPath.rt
                    direction: glassPath.inverse(PathArc.Counterclockwise)
                    useLargeArc: false
                }

                PathLine {
                    x: glassPath.px(glassPath.rb, glassPath.thick - glassPath.rb)
                    y: glassPath.py(glassPath.rb, glassPath.thick - glassPath.rb)
                }

                PathArc {
                    x: glassPath.px(0, glassPath.thick)
                    y: glassPath.py(0, glassPath.thick)
                    radiusX: glassPath.rb
                    radiusY: glassPath.rb
                    direction: glassPath.inverse(PathArc.Clockwise)
                    useLargeArc: false
                }
            }
        }

        Item {
            id: contentClip
            // El cuerpo se pega al filo; el recorte del revelado entra desde
            // el lado de dentro.
            x: dock.vertical ? (dock.atLeft ? 0 : parent.width - width) : 0
            y: dock.vertical ? 0 : (dock.atTop ? 0 : parent.height - height)
            width: dock.vertical ? Theme.dockHeight : parent.width
            height: dock.vertical ? parent.height : Theme.dockHeight
            clip: true

            Row {
                id: dockRow
                visible: !dock.vertical
                anchors.verticalCenter: parent.verticalCenter
                x: Math.round((dock.dockWidth - dockRow.implicitWidth) / 2)
                spacing: 6

                // Qt 6 quitó la propiedad `alignment` de las filas: los hijos
                // se quedan arriba, pegados al borde del cristal. La fila ya
                // no los mueve en vertical, así que se centran aquí.
                MusicWidget {
                    id: musicWidget
                    y: Math.round((dockRow.height - height) / 2)
                    onActivated: dock.openMusicMenu()
                }

                Repeater {
                    model: dock.dockApps

                    delegate: DockApp {
                        y: Math.round((dockRow.height - height) / 2)
                        app: modelData
                        instanceCount: dock.countFor(modelData)
                        focused: dock.isFocused(modelData)
                        onActivated: function(newInstance) {
                            appMenu.close();
                            dock.launch(modelData, newInstance);
                        }
                        onMenuRequested: function(anchor) {
                            dock.openAppMenu(modelData, anchor);
                        }
                    }
                }
            }

            Column {
                id: dockColumn
                visible: dock.vertical
                anchors.horizontalCenter: parent.horizontalCenter
                // Centrada sobre el largo plegado: al desplegar, la carátula se
                // queda donde está y la tarjeta sólo crece hacia abajo.
                y: dock.vertical
                    ? Math.round((dock.collapsedLength - dock.restContent) / 2)
                    : Math.round((dock.dockWidth - dockColumn.implicitHeight) / 2)
                spacing: 6

                // En columna no cabe el reproductor entero: sólo la carátula,
                // que se estira con los controles al pasar el puntero.
                MusicWidget {
                    id: musicTile
                    compact: true
                    expanded: dock.musicExpanded
                    x: Math.round((dockColumn.width - width) / 2)
                    onActivated: dock.openMusicMenu()
                }

                Repeater {
                    model: dock.dockApps

                    delegate: DockApp {
                        x: Math.round((dockColumn.width - width) / 2)
                        app: modelData
                        instanceCount: dock.countFor(modelData)
                        focused: dock.isFocused(modelData)
                        onActivated: function(newInstance) {
                            appMenu.close();
                            dock.launch(modelData, newInstance);
                        }
                        onMenuRequested: function(anchor) {
                            dock.openAppMenu(modelData, anchor);
                        }
                    }
                }
            }
        }
    }

    function animateDockWidth(next) {
        const current = dock.dockWidth;
        widthBounce.stop();
        if (next === current)
            return;
        const grow = next > current;
        const distance = Math.abs(next - current);
        const overshoot = Math.min(16, Math.max(5, Math.round(distance * 0.30)));

        if (grow) {
            widthBounceOut.from = current;
            widthBounceOut.to = next + overshoot;
            widthBounceOut.duration = 130;
            widthBounceBack.from = next + overshoot;
            widthBounceBack.to = next;
            widthBounceBack.duration = 190;
        } else {
            widthBounceOut.from = current;
            widthBounceOut.to = next;
            widthBounceOut.duration = 180;
            widthBounceBack.from = next;
            widthBounceBack.to = next;
            widthBounceBack.duration = 1;
        }

        widthBounce.restart();
    }

    function normalizeId(id) {
        return String(id || "").toLowerCase().replace(/\.desktop$/, "");
    }

    function entryMatchesAppId(entry, id) {
        return DockEntries.matchesAppId(entry, id);
    }

    // El appId de una ventana no siempre coincide con el id del .desktop ni
    // con el nombre del icono. Se busca por id, por heurística y finalmente
    // por StartupWMClass/nombre antes de caer al icono genérico.
    function desktopEntryForAppId(value) {
        const raw = String(value || "");
        if (!raw)
            return null;

        const id = normalizeId(raw);
        if (dock.appEntryCache[id] !== undefined)
            return dock.appEntryCache[id];

        const candidates = [raw, id];
        for (let i = 0; i < candidates.length; ++i) {
            const entry = DesktopEntries.byId(candidates[i]);
            if (entry) {
                dock.appEntryCache[id] = entry;
                return entry;
            }
        }

        const guessed = DesktopEntries.heuristicLookup(raw)
            || DesktopEntries.heuristicLookup(id)
            || DesktopEntries.heuristicLookup(displayName(raw));
        if (guessed) {
            dock.appEntryCache[id] = guessed;
            return guessed;
        }

        const entries = DesktopEntries.applications
            ? DesktopEntries.applications.values
            : [];
        for (let i = 0; i < entries.length; ++i) {
            const entry = entries[i];
            if (entry && DockEntries.matchesAppId(entry, raw)) {
                if (entries.length > 0)
                    dock.appEntryCache[id] = entry;
                return entry;
            }
        }

        if (entries.length > 0)
            dock.appEntryCache[id] = null;
        return null;
    }

    function matchesApp(app, appId) {
        const key = normalizeId(appId);
        if (!key)
            return false;

        const candidates = app.matches || [app.entryId];
        for (let i = 0; i < candidates.length; ++i) {
            if (key === normalizeId(candidates[i]))
                return true;
        }
        return false;
    }

    function appId(app) {
        if (!app)
            return "";
        if (app.focusId)
            return normalizeId(app.focusId);
        if (app.matches && app.matches.length > 0)
            return normalizeId(app.matches[0]);
        return normalizeId(app.entryId || app.key);
    }

    function isPinned(app) {
        const id = appId(app);
        if (!id)
            return false;
        for (let i = 0; i < dock.pinnedApps.length; ++i) {
            if (matchesApp(dock.pinnedApps[i], id))
                return true;
        }
        return false;
    }

    function desktopEntry(app) {
        if (!app)
            return null;
        const value = app.focusId
            || (app.matches && app.matches[0])
            || app.entryId
            || app.key;
        return desktopEntryForAppId(value)
            || DesktopEntries.heuristicLookup(app.name);
    }

    function cleanCommand(command) {
        const result = [];
        for (let i = 0; i < (command || []).length; ++i) {
            const arg = String(command[i]);
            if (arg.indexOf("@@") !== 0)
                result.push(arg);
        }
        return result;
    }

    function matchesFor(app, id) {
        const result = [];
        const candidates = [id, app.focusId, app.entryId]
            .concat(app.matches || []);
        for (let i = 0; i < candidates.length; ++i) {
            const candidate = normalizeId(candidates[i]);
            if (candidate && result.indexOf(candidate) === -1)
                result.push(candidate);
        }
        return result;
    }

    function savePinned(list) {
        pinsAdapter.pinned = list;
        pinsFile.writeAdapter();
    }

    function pinApp(app) {
        if (!app || isPinned(app))
            return;

        const entry = desktopEntry(app);
        const id = entry ? entry.id : appId(app);
        const command = entry && entry.command && entry.command.length > 0
            ? cleanCommand(entry.command)
            : (app.command || []);
        const newCommand = app.newCommand && app.newCommand.length > 0
            ? app.newCommand
            : command;

        const pinnedApp = {
            key: "pinned:" + id,
            name: entry && entry.name ? entry.name : app.name,
            entryId: entry ? entry.id + ".desktop" : (app.entryId || id + ".desktop"),
            icon: entry && entry.icon ? entry.icon : app.icon,
            matches: matchesFor(app, id),
            command: command,
            newCommand: newCommand,
            pinned: true
        };

        savePinned(dock.pinnedApps.concat([pinnedApp]));
    }

    function unpinApp(app) {
        const id = appId(app);
        if (!id)
            return;
        const next = [];
        for (let i = 0; i < dock.pinnedApps.length; ++i) {
            if (!matchesApp(dock.pinnedApps[i], id))
                next.push(dock.pinnedApps[i]);
        }
        if (next.length !== dock.pinnedApps.length)
            savePinned(next);
    }

    function openAppMenu(app, anchorItem) {
        if (!app || !anchorItem)
            return;

        // Segundo clic derecho sobre el mismo icono = cerrar. Si el menú
        // estaba abierto en otra app, se cierra y se abre en la nueva.
        const id = appId(app);
        const openId = appMenu.app ? appId(appMenu.app) : "";
        if (appMenu.opened && id && id === openId) {
            appMenu.close();
            return;
        }

        if (appMenu.opened)
            appMenu.close();
        appMenu.app = app;
        appMenu.entry = desktopEntry(app);
        appMenu.pinned = isPinned(app);
        appMenu.anchorItem = anchorItem;
        Qt.callLater(function() { appMenu.open(); });
    }

    function countFor(app) {
        let count = 0;
        const ids = dock.windowAppIds || [];
        for (let i = 0; i < ids.length; ++i) {
            if (matchesApp(app, ids[i]))
                ++count;
        }
        return count;
    }

    function isFocused(app) {
        return matchesApp(app, dock.activeAppId);
    }

    function displayName(appId) {
        let name = normalizeId(appId);
        if (name.indexOf("org.kde.") === 0)
            name = name.substring(8);
        name = name.replace(/[._-]+/g, " ").trim();
        return name ? name.charAt(0).toUpperCase() + name.slice(1) : appId;
    }

    // Los nombres con los que se puede llamar a una app: id del .desktop,
    // appId de la ventana y clase de arranque. Se pasan todos porque el
    // nombre de la ventana no siempre coincide con el del icono.
    function targetIdsFor(app) {
        const ids = [];
        const candidates = [app.focusId, app.entryId].concat(app.matches || []);
        for (let i = 0; i < candidates.length; ++i) {
            const id = normalizeId(candidates[i]);
            if (id && ids.indexOf(id) === -1)
                ids.push(id);
        }
        return ids;
    }

    // KWin decide qué hacer con la ventana: si está minimizada la restaura, si
    // la app está enfocada la minimiza y si no la enfoca.
    function activateApp(app) {
        const ids = targetIdsFor(app);
        if (ids.length === 0)
            return;

        windowActionProcess.target = ids.join("|");
        windowActionProcess.active = dock.activeAppId;

        // Una acción en curso no se puede cambiar: se cancela y se lanza la
        // nueva, que si no se perdería el clic.
        if (windowActionProcess.running) {
            windowActionProcess.running = false;
            Qt.callLater(function() {
                windowActionProcess.running = true;
            });
            return;
        }

        windowActionProcess.running = true;
    }

    function launch(app, newInstance) {
        // Las apps que ya tienen ventanas se enfocan en vez de duplicarse.
        if (app.pinned === false || (!newInstance && countFor(app) > 0)) {
            activateApp(app);
            return;
        }

        const command = newInstance ? app.newCommand : app.command;
        if (command && command.length > 0) {
            Quickshell.execDetached(command);
            return;
        }

        // Respaldo para apps ancladas sin comando resuelto por DesktopEntries.
        if (app.entryId)
            Quickshell.execDetached(["gio", "launch", app.entryId]);
    }

    // Capa modal a pantalla completa para cerrar el menú al pulsar fuera.
    // El hueco del dock deja pasar los clics a los iconos, igual que la
    // barrera que usa el menú de la bandeja.
    PanelWindow {
        id: menuClickCatcher
        screen: dock.screen
        visible: appMenu.opened
        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }
        exclusiveZone: 0
        focusable: false
        color: "transparent"

        mask: Region {
            x: 0
            y: 0
            width: dock.screen ? dock.screen.width : dock.width
            height: dock.screen ? dock.screen.height : dock.height

            Region {
                x: dock.x + hitArea.x
                y: dock.y + hitArea.y
                width: hitArea.width
                height: hitArea.height
                intersection: Intersection.Subtract
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onPressed: appMenu.close()
        }
    }
}

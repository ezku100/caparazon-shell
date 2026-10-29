import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../../theme"
import "../icons"
import "DockEntries.js" as DockEntries

PanelWindow {
    id: dock

    required property var modelData
    property string activeAppId: ""
    property var windowAppIds: []
    property var trayMenuState: null

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
        id: focusProcess
        running: false
        property string target: ""

        command: [
            "bash", "-c",
            "target=\"$1\"; " +
            "case \"$target\" in ''|*[!A-Za-z0-9._-]*) exit 1;; esac; " +
            "tmp=\"${XDG_RUNTIME_DIR:-/tmp}/caparazon-focus-$$.js\"; " +
            "sed \"s|__TARGET__|$target|g\" \"$2\" > \"$tmp\"; " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting " +
            "--method org.kde.kwin.Scripting.unloadScript caparazon-focus >/dev/null 2>&1; " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting " +
            "--method org.kde.kwin.Scripting.loadScript \"$tmp\" caparazon-focus >/dev/null; " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting " +
            "--method org.kde.kwin.Scripting.start >/dev/null; " +
            "rm -f \"$tmp\"",
            "bash",
            focusProcess.target,
            Quickshell.shellPath("modules/bar/KWinFocusApp.js")
        ]
    }

    readonly property int targetWidth: Math.max(308, dockRow.implicitWidth + 2 * Theme.padH + 16)
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
        animateDockWidth(targetWidth);
    }
    readonly property int bottomGap: 0

    anchors {
        bottom: true
        left: true
        right: true
    }

    margins {
        bottom: dock.bottomGap
        left: 0
        right: 0
    }

    implicitHeight: Theme.dockHeight + Theme.shadowPad
    exclusiveZone: Theme.dockHeight + dock.bottomGap
    color: "transparent"

    mask: Region { item: hitArea }

    Item {
        id: hitArea
        x: Math.round((parent.width - dock.dockWidth) / 2)
        y: Theme.shadowPad
        width: dock.dockWidth
        height: Theme.dockHeight
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
        anchors.bottom: parent.bottom
        x: Math.round((parent.width - width) / 2)
        width: dock.dockWidth + 2 * Theme.shadowPad
        height: dock.reveal * (Theme.dockHeight + Theme.shadowPad)
        clip: true
        opacity: 0.25 + 0.75 * dock.reveal

        MultiEffect {
            id: elevation
            source: glass
            anchors {
                left: parent.left
                leftMargin: Theme.shadowPad
                bottom: parent.bottom
            }
            width: parent.width - 2 * Theme.shadowPad
            height: Theme.dockHeight

            blurMax: 32
            shadowEnabled: true
            shadowColor: Theme.shadowColor
            shadowOpacity: Theme.shadowOpacity
            shadowBlur: Theme.shadowBlur
            shadowHorizontalOffset: 0
            shadowVerticalOffset: -Theme.shadowOffsetY
        }

        Shape {
            id: glass
            anchors {
                left: parent.left
                leftMargin: Theme.shadowPad
                right: parent.right
                rightMargin: Theme.shadowPad
                bottom: parent.bottom
            }
            height: Theme.dockHeight
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                id: glassPath
                readonly property int rt: Theme.radius
                readonly property int rb: Theme.radiusTop

                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Theme.surface

                // Inferior intacta: el cuerpo se abre hacia el borde.
                // Solo los dos arcos superiores curvan hacia adentro.
                startX: 0
                startY: glass.height

                PathLine { x: glass.width; y: glass.height }

                PathArc {
                    x: glass.width - glassPath.rb
                    y: glass.height - glassPath.rb
                    radiusX: glassPath.rb
                    radiusY: glassPath.rb
                    direction: PathArc.Clockwise
                    useLargeArc: false
                }

                PathLine { x: glass.width - glassPath.rb; y: glassPath.rt }

                PathArc {
                    x: glass.width - glassPath.rb - glassPath.rt
                    y: 0
                    radiusX: glassPath.rt
                    radiusY: glassPath.rt
                    direction: PathArc.Counterclockwise
                    useLargeArc: false
                }

                PathLine { x: glassPath.rb + glassPath.rt; y: 0 }

                PathArc {
                    x: glassPath.rb
                    y: glassPath.rt
                    radiusX: glassPath.rt
                    radiusY: glassPath.rt
                    direction: PathArc.Counterclockwise
                    useLargeArc: false
                }

                PathLine { x: glassPath.rb; y: glass.height - glassPath.rb }

                PathArc {
                    x: 0
                    y: glass.height
                    radiusX: glassPath.rb
                    radiusY: glassPath.rb
                    direction: PathArc.Clockwise
                    useLargeArc: false
                }
            }
        }

        Item {
            id: contentClip
            anchors.fill: glass
            clip: true

            Row {
                id: dockRow
                anchors.verticalCenter: parent.verticalCenter
                x: Math.round((dock.dockWidth - dockRow.implicitWidth) / 2)
                spacing: 6

                MusicWidget {
                    id: musicWidget
                }

                Repeater {
                    model: dock.dockApps

                    delegate: DockApp {
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

    function focusApp(app) {
        const id = app.focusId || (app.matches ? app.matches[0] : "");
        if (!id)
            return;

        focusProcess.target = id;
        focusProcess.running = true;
    }

    function launch(app, newInstance) {
        // Las apps que ya tienen ventanas se enfocan en vez de duplicarse.
        if (app.pinned === false || (!newInstance && countFor(app) > 0)) {
            focusApp(app);
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

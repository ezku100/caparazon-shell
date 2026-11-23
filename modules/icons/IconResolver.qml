pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "IconNames.js" as IconNames

// Resolvedor de iconos de la shell.
//
// Qt busca en el tema activo, sus herencias y los directorios de iconos
// estándar, así que el nombre exacto casi siempre funciona. Quedan tres
// huecos: las rutas (con o sin extensión), las URL file: y los iconos que el
// usuario deja fuera de un tema —al lado de su .desktop, en ~/.icons o en una
// subcarpeta suelta—. Los dos primeros se resuelven por archivo; el tercero se
// indexa una vez al arrancar.
//
// En niri no hay nadie que ponga un tema en Qt: el config de niri fija el tema
// y la shell busca ella misma los iconos en el directorio de ese tema. En KDE
// se deja todo como estaba: el tema lo pone KDE y Qt lo busca.
Singleton {
    id: root

    readonly property string genericIcon: "application-x-executable"

    // nombre base -> ruta absoluta, para iconos fuera de los temas.
    property var userIcons: ({})

    // Tema de iconos de la sesión; en niri lo dice el config de niri.
    property string iconTheme: "Papirus-Dark"
    property var themeSearchOrder: []

    readonly property string niriConfigPath: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME") || "";
        const base = (xdg && xdg.length > 0) ? xdg : home + "/.config";
        return base + "/niri/config.kdl";
    }

    // El tema vive en el include (dueño de CAPARAZON_ICON_THEME): --set
    // escribe aquí y config.kdl no cambia, así que hay que vigilarlo.
    readonly property string niriEnvConfigPath: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME") || "";
        const base = (xdg && xdg.length > 0) ? xdg : home + "/.config";
        return base + "/niri/config.d/40-environment.kdl";
    }

    function reloadThemeQuery() {
        themeQuery.running = false;
        themeQuery.running = true;
    }

    readonly property var userIconRoots: {
        const home = Quickshell.env("HOME") || "";
        const xdg = Quickshell.env("XDG_DATA_HOME");
        const data = (xdg && xdg.length > 0) ? xdg : home + "/.local/share";
        return [
            data + "/applications",
            data + "/icons",
            data + "/pixmaps",
            home + "/.icons",
            data + "/flatpak/exports/share/applications",
            data + "/flatpak/exports/share/icons"
        ];
    }

    // Directorios de todos los temas de la búsqueda: dentro de cada tema los
    // iconos van anidados en carpetas de tamaño, así que se buscan más profundo.
    readonly property var themeIconRoots: {
        if (!CompositorService.niri)
            return [];
        const home = Quickshell.env("HOME") || "";
        const xdgData = Quickshell.env("XDG_DATA_HOME");
        const data = (xdgData && xdgData.length > 0) ? xdgData : home + "/.local/share";
        const systemDirs = (Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":");
        const themes = root.themeSearchOrder.length > 0
            ? root.themeSearchOrder
            : [root.iconTheme, "hicolor"];
        const roots = [];
        for (let t = 0; t < themes.length; ++t) {
            const theme = String(themes[t] || "");
            if (theme.length === 0)
                continue;
            roots.push(data + "/icons/" + theme, home + "/.icons/" + theme);
            for (let i = 0; i < systemDirs.length; ++i)
                roots.push(systemDirs[i] + "/icons/" + theme);
        }
        return roots;
    }

    Component.onCompleted: {
        iconScan.running = true;
        themeQuery.running = true;
    }

    // Las raíces del tema dependen del compositor y del tema, que llegan
    // después por el CLI: cuando cambian, hay que volver a indexar.
    onThemeIconRootsChanged: root.rescan()

    function rescan() {
        iconScan.running = false;
        iconScan.running = true;
    }

    Process {
        id: themeQuery

        command: ["caparazon-wm", "icon-theme"]

        stdout: StdioCollector {
            id: themeOutput

            onStreamFinished: {
                try {
                    const payload = JSON.parse(String(themeOutput.text || "{}"));
                    const name = String(payload.current || "");
                    const order = Array.isArray(payload.search) && payload.search.length > 0
                        ? payload.search.map((entry) => String(entry))
                        : (name.length > 0 ? [name, "hicolor"] : []);
                    let changed = false;
                    if (name.length > 0 && name !== root.iconTheme) {
                        root.iconTheme = name;
                        changed = true;
                    }
                    if (JSON.stringify(order) !== JSON.stringify(root.themeSearchOrder)) {
                        root.themeSearchOrder = order;
                        changed = true;
                    }
                    if (changed)
                        root.rescan();
                } catch (error) {
                    console.warn("caparazon: no se pudo leer el tema de iconos", error);
                }
            }
        }
    }

    FileView {
        id: niriConfig

        path: root.niriConfigPath
        watchChanges: true
        printErrors: false

        onFileChanged: {
            reload();
            root.reloadThemeQuery();
        }
    }

    FileView {
        id: niriEnvConfig

        path: root.niriEnvConfigPath
        watchChanges: true
        printErrors: false

        onFileChanged: {
            reload();
            root.reloadThemeQuery();
        }
    }

    Process {
        id: iconScan

        command: ["bash", "-c",
            'for d in "$@"; do depth=2; case "$d" in deep:*) depth=4; d="${d#deep:}";; esac; [ -d "$d" ] && find "$d" -maxdepth "$depth" \\( -type f -o -type l \\) -printf "%f\\t%p\\n"; done 2>/dev/null',
            "caparazon-icons"].concat(root.userIconRoots).concat(root.themeIconRoots.map((path) => "deep:" + path))

        stdout: StdioCollector {
            id: iconOutput

            onStreamFinished: {
                const map = {};
                const lines = String(iconOutput.text || "").split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const tab = lines[i].indexOf("\t");
                    if (tab < 1)
                        continue;
                    const name = IconNames.stem(lines[i].slice(0, tab));
                    if (name.length === 0)
                        continue;
                    const path = lines[i].slice(tab + 1);
                    const current = map[name];
                    if (current !== undefined) {
                        if (!CompositorService.niri)
                            continue;
                        if (IconNames.iconRank(path, root.themeSearchOrder) <= IconNames.iconRank(current, root.themeSearchOrder))
                            continue;
                    }
                    map[name] = path;
                }
                root.userIcons = map;
            }
        }
    }

    // URL del icono si algo lo resuelve; "" si no hay ninguno. Las rutas se
    // validan con iconPath(check), que además adivina la extensión; si el
    // archivo no está (disco sin montar, ruta vieja) se prueba su nombre.
    function resolved(name) {
        const raw = String(name || "").trim();
        const kind = IconNames.iconKind(raw);

        if (kind === "url")
            return raw;
        if (kind === "path") {
            const direct = String(Quickshell.iconPath(raw, true));
            if (direct.length > 0)
                return direct;
            return root.byName(IconNames.nameFromPath(raw));
        }
        if (kind !== "name")
            return "";

        return root.byName(raw);
    }

    function indexedByName(name) {
        const names = IconNames.candidates(name);
        for (let i = 0; i < names.length; ++i) {
            const indexed = root.indexed(names[i]);
            if (indexed.length > 0)
                return indexed;
        }
        return "";
    }

    // En niri Qt no sabe qué tema hay: su búsqueda devuelve el tema congelado
    // al arrancar, así que los nombres sólo se resuelven desde el índice.
    function byName(name) {
        if (CompositorService.niri)
            return root.indexedByName(name);
        const names = IconNames.candidates(name);
        for (let i = 0; i < names.length; ++i) {
            const path = String(Quickshell.iconPath(names[i], true));
            if (path.length > 0)
                return path;
        }
        return root.indexedByName(name);
    }

    // Primer nombre que resuelva en el tema o en el índice; "" si ninguno.
    // Los iconos propios de la shell (categorías, indicadores de la barra) no
    // pueden depender de una ruta de un tema concreto: se piden por nombre y
    // cada tema pone el suyo.
    function themed(names) {
        for (let i = 0; i < names.length; ++i) {
            const found = root.resolved(names[i]);
            if (found.length > 0)
                return found;
        }
        return "";
    }

    // Primer nombre disponible o, si no hay ninguno, el genérico.
    function firstOf(names) {
        const found = root.themed(names);
        return found.length > 0 ? found : root.source(root.genericIcon, "");
    }

    // Igual que themed(), pero sin el respaldo por prefijo de iconPath: sirve
    // para saber si el tema trae el icono exacto y no uno de nombre parecido.
    function exactThemed(names) {
        for (let i = 0; i < names.length; ++i) {
            if (Quickshell.hasThemeIcon(names[i]))
                return String(Quickshell.iconPath(names[i], ""));
        }
        return "";
    }

    // Leer userIcons crea la dependencia que repinta las tarjetas cuando el
    // índice termina de llenarse.
    function indexed(name) {
        const map = root.userIcons;
        const hit = map[name];
        return hit ? String(Qt.resolvedUrl(hit)) : "";
    }

    // URL del icono: la resuelta o, en su defecto, el icono genérico.
    function source(name, fallback) {
        const found = root.resolved(name);
        if (found.length > 0)
            return found;
        const generic = fallback && fallback.length > 0 ? fallback : root.genericIcon;
        if (CompositorService.niri)
            return root.indexedByName(generic);
        return String(Quickshell.iconPath(generic, ""));
    }
}

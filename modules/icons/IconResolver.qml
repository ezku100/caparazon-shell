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
Singleton {
    id: root

    readonly property string genericIcon: "application-x-executable"

    // nombre base -> ruta absoluta, para iconos fuera de los temas.
    property var userIcons: ({})

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

    Component.onCompleted: iconScan.running = true

    Process {
        id: iconScan

        command: ["bash", "-c",
            'for d in "$@"; do [ -d "$d" ] && find "$d" -maxdepth 2 -type f -printf "%f\\t%p\\n"; done 2>/dev/null',
            "caparazon-icons"].concat(root.userIconRoots)

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
                    if (name.length === 0 || map[name])
                        continue;
                    map[name] = lines[i].slice(tab + 1);
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

    // Prueba los nombres alternativos en el tema y, si no están, en el índice
    // de iconos del usuario.
    function byName(name) {
        const names = IconNames.candidates(name);
        for (let i = 0; i < names.length; ++i) {
            const path = String(Quickshell.iconPath(names[i], true));
            if (path.length > 0)
                return path;
        }
        for (let i = 0; i < names.length; ++i) {
            const indexed = root.indexed(names[i]);
            if (indexed.length > 0)
                return indexed;
        }
        return "";
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
        return String(Quickshell.iconPath(generic, ""));
    }
}

pragma Singleton
import Quickshell
import QtQuick
import "IconNames.js" as IconNames

// Resolvedor de iconos de la shell.
//
// Qt ya busca en el tema activo de Plasma y en todos los temas instalados,
// así que el nombre exacto casi siempre funciona. Sólo falta cuando la app
// no trae .desktop o su appId no coincide con el nombre del icono: entonces
// se prueban los nombres alternativos de IconNames.js antes de caer al icono
// genérico, para que el dock nunca muestre un icono que no toca.
QtObject {
    id: root

    readonly property string genericIcon: "application-x-executable"

    // URL del icono si algún nombre candidato lo resuelve; "" si no hay
    // ninguno. Las rutas y las URL file: se devuelven tal cual, convertidas a
    // texto: Qt.resolvedUrl() devuelve un objeto url sin `.length`, así que
    // compararlo con "" daba siempre falso y el icono caía al genérico.
    function resolved(name) {
        const raw = String(name || "").trim();
        const kind = IconNames.iconKind(raw);
        if (kind === "url")
            return raw;
        if (kind === "path")
            return String(Qt.resolvedUrl(raw));
        if (kind !== "name")
            return "";

        const names = IconNames.candidates(raw);
        for (let i = 0; i < names.length; ++i) {
            if (Quickshell.hasThemeIcon(names[i]))
                return String(Quickshell.iconPath(names[i], root.genericIcon));
        }
        return "";
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

// Nombres de icono que se prueban cuando el nombre exacto no existe.
//
// Qt ya busca en el tema activo y en todos los temas instalados, así que un
// icono sólo falta cuando la app se llama de una forma y su icono se llama de
// otra: "com.obsproject.Studio" frente a "obsproject", o "Studio" frente a
// "studio". Aquí se generan los nombres alternativos, del más específico al
// más general, para que el resolvedor pueda probarlos uno a uno.
//
// El estado es una lista plana de nombres únicos; no se modifica nada fuera.

var SYMBOLIC_SUFFIX = "-symbolic";

var ICON_EXTENSIONS = [".png", ".svg", ".xpm", ".jpg", ".jpeg", ".webp"];

// Nombre de icono a partir de un archivo: quita sólo extensiones de imagen,
// para poder buscar en el índice de iconos del usuario.
function stem(fileName) {
    var raw = typeof fileName === "string" ? fileName.trim() : "";
    var dot = raw.lastIndexOf(".");
    if (dot <= 0)
        return raw;
    if (ICON_EXTENSIONS.indexOf(raw.slice(dot).toLowerCase()) === -1)
        return raw;
    return raw.slice(0, dot);
}

// Nombre de icono que sugiere una ruta: último segmento, sin extensión.
function nameFromPath(path) {
    var raw = typeof path === "string" ? path.trim() : "";
    var slash = raw.lastIndexOf("/");
    return stem(slash === -1 ? raw : raw.slice(slash + 1));
}

// Clasifica lo que trae un .desktop o KWin: ruta absoluta, URL file: o nombre
// de tema. Sin esta distinción una ruta se trata como nombre de tema, no se
// encuentra y el icono acaba en el genérico.
function iconKind(name) {
    var raw = typeof name === "string" ? name.trim() : "";
    if (raw.length === 0)
        return "empty";
    if (raw.indexOf("file:") === 0)
        return "url";
    if (raw.charAt(0) === "/")
        return "path";
    return "name";
}

// Devuelve los nombres de icono a probar, en orden de prioridad.
// El nombre exacto va siempre el primero: si existe, nada más cambia.
function candidates(name) {
    var result = [];
    var raw = typeof name === "string" ? name.trim() : "";
    if (iconKind(raw) !== "name")
        return result;

    function push(value) {
        if (!value || value.length === 0)
            return;
        if (result.indexOf(value) !== -1)
            return;
        result.push(value);
    }

    push(raw);

    // Un icono simbólico también puede existir sin el sufijo.
    var stem = raw.endsWith(SYMBOLIC_SUFFIX)
        ? raw.slice(0, raw.length - SYMBOLIC_SUFFIX.length)
        : raw;
    push(stem);
    push(stem + SYMBOLIC_SUFFIX);
    push(stem.toLowerCase());
    push(stem.toLowerCase() + SYMBOLIC_SUFFIX);

    // Los appId de KDE y Electron usan dominio invertido:
    // com.obsproject.Studio -> obsproject.Studio -> Studio.
    var parts = raw.split(".");
    for (var drop = 1; drop < parts.length; ++drop) {
        var rest = parts.slice(drop).join(".");
        push(rest);
        push(rest.toLowerCase());
        if (rest.indexOf(".") === -1)
            continue;
        var head = rest.split(".")[0];
        push(head);
        push(head.toLowerCase());
    }

    return result;
}

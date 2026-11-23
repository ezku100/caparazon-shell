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

// Quickshell.iconPath(name, fallback) devuelve image://icon/name?fallback=…;
// si esa URL se reentra como nombre, la query ensucia la búsqueda.
function stripQuery(name) {
    var raw = typeof name === "string" ? name.trim() : "";
    var q = raw.indexOf("?");
    return q === -1 ? raw : raw.slice(0, q).trim();
}

// Nombre de icono a partir de un archivo: quita sólo extensiones de imagen,
// para poder buscar en el índice de iconos del usuario.
function stem(fileName) {
    var raw = stripQuery(fileName);
    var dot = raw.lastIndexOf(".");
    if (dot <= 0)
        return raw;
    if (ICON_EXTENSIONS.indexOf(raw.slice(dot).toLowerCase()) === -1)
        return raw;
    return raw.slice(0, dot);
}

// Nombre de icono que sugiere una ruta: último segmento, sin extensión.
function nameFromPath(path) {
    var raw = stripQuery(path);
    var slash = raw.lastIndexOf("/");
    return stem(slash === -1 ? raw : raw.slice(slash + 1));
}

// Clasifica lo que trae un .desktop, KWin o un icono ya resuelto: ruta
// absoluta, URL (file:, image:, qrc:) o nombre de tema. Sin esta distinción
// una ruta se trata como nombre de tema, no se encuentra y el icono acaba en
// el genérico; y una URL image:// ya resuelta se volvería a buscar como tema.
function iconKind(name) {
    var raw = typeof name === "string" ? name.trim() : "";
    if (raw.length === 0)
        return "empty";
    if (raw.indexOf("file:") === 0 || raw.indexOf("image:") === 0
            || raw.indexOf("qrc:") === 0)
        return "url";
    if (raw.charAt(0) === "/")
        return "path";
    return "name";
}

// Devuelve los nombres de icono a probar, en orden de prioridad.
// El nombre exacto va siempre el primero: si existe, nada más cambia.
function candidates(name) {
    var result = [];
    var raw = stripQuery(name);
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

// Valor de una variante de icono: cuánto merece frente a las demás.
//
// Un tema trae el mismo icono en varias carpetas de tamaño (16x16, 48x48,
// scalable...). En niri la shell los busca ella misma, así que de todas las
// copias se queda con la mejor: la más grande y, a igual tamaño, la vectorial.
var ICON_SIZE_RANKS = {
    "scalable": 100,
    "128x128": 90,
    "96x96": 85,
    "72x72": 80,
    "64x64": 75,
    "48x48": 70,
    "32x32": 60,
    "24x24": 50,
    "22x22": 45,
    "16x16": 30,
    "8x8": 10,
    "4x4": 5,
};

var ICON_DEFAULT_RANK = 55;

// Cada puesto en la lista de búsqueda vale más que cualquier tamaño: el icono
// del tema activo gana aunque sea de 16x16 y el heredado sea scalable.
var ICON_THEME_RANK_STEP = 1000;

// Nombre del tema al que pertenece un archivo del índice. Sólo cuenta si tras
// "icons/<tema>" queda algo: data/icons/foo.png es un icono suelto, no un tema.
function themeFromPath(filePath) {
    var raw = typeof filePath === "string" ? filePath.trim() : "";
    var parts = raw.split("/");
    for (var index = 0; index < parts.length - 2; ++index) {
        if (parts[index] !== "icons" && parts[index] !== ".icons")
            continue;
        var candidate = parts[index + 1];
        if (candidate.length > 0 && index + 2 < parts.length)
            return candidate;
    }
    return "";
}

function themeRank(filePath, searchOrder) {
    var order = Array.isArray(searchOrder) ? searchOrder : [];
    var theme = themeFromPath(filePath);
    if (order.length === 0 || theme.length === 0)
        return 0;
    for (var index = 0; index < order.length; ++index) {
        if (String(order[index]) === theme)
            return (order.length - index) * ICON_THEME_RANK_STEP;
    }
    return 0;
}

function iconRank(filePath, searchOrder) {
    var raw = typeof filePath === "string" ? filePath.trim() : "";
    if (raw.length === 0)
        return 0;

    var parts = raw.split("/");
    var rank = ICON_DEFAULT_RANK;
    for (var index = 0; index < parts.length - 1; ++index) {
        var folder = parts[index].replace(/@\d+x$/, "");
        if (folder !== "scalable" && !/^\d+x\d+$/.test(folder))
            continue;
        var value = ICON_SIZE_RANKS[folder];
        rank = value === undefined ? ICON_DEFAULT_RANK : value;
    }

    // El vector se ve nítido a cualquier tamaño: gana al mapa de bits.
    if (raw.toLowerCase().endsWith(".svg"))
        rank += 10;

    return rank + themeRank(raw, searchOrder);
}

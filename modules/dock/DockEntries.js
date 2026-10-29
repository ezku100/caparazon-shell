// Emparejamiento entre una ventana y su entrada de .desktop.
//
// El dock no sabe qué .desktop corresponde a cada ventana: KWin sólo publica
// el appId (el StartupWMClass de la app) y el nombre del .desktop es otra
// cosa. Para Prism, por ejemplo, la ventana publica
// "org.prismlauncher.PrismLauncher" y su .desktop es "prism_launcher".
//
// Aquí se comparan los dos lados sin depender del compositor: minúsculas,
// sin sufijos ".desktop" y sin separadores, porque cada app escribe los
// separadores a su manera ("prism_launcher", "PrismLauncher",
// "org.prismlauncher.PrismLauncher" son la misma app).

// Normaliza un id: minúsculas y sin el sufijo ".desktop".
function normalizeId(value) {
    var raw = typeof value === "string" ? value.trim() : "";
    return raw.toLowerCase().replace(/\.desktop$/, "");
}

// Versión compacta: sólo letras y números, para que los separadores no
// decidan si dos nombres son el mismo.
function compactId(value) {
    var raw = typeof value === "string" ? value.trim() : "";
    return raw.toLowerCase().replace(/[^a-z0-9]/g, "");
}

// Última parte de un appId con dominio: "org.prismlauncher.PrismLauncher"
// deja "PrismLauncher", que es justo la clase de arranque que declara el
// .desktop.
function lastSegment(value) {
    var raw = typeof value === "string" ? value.trim() : "";
    if (raw.length === 0)
        return "";
    var parts = raw.split(".");
    return parts[parts.length - 1];
}

// Comprueba si una cadena empieza o termina por otra con un límite de
// separador (. _ - o fin de cadena). Se usa sobre el id en minúsculas, sin
// quitar los separadores, para que "veadotube-mini" casara con "veadotube"
// pero "steamroller" no casara con "steam".
function bounded(value, key, atStart) {
    var raw = typeof value === "string" ? value.toLowerCase() : "";
    if (raw.length === 0 || key.length === 0)
        return false;
    var index = atStart ? raw.indexOf(key) : raw.lastIndexOf(key);
    if (index === -1)
        return false;
    var boundaryIndex = atStart ? key.length : raw.length - key.length;
    if (boundaryIndex === 0 || boundaryIndex === raw.length)
        return true;
    var char = atStart ? raw.charAt(boundaryIndex) : raw.charAt(boundaryIndex - 1);
    return /[._-]/.test(char);
}

// ¿Esta entrada de .desktop corresponde a este appId de ventana?
//
// Se prueban, en orden: la clase de arranque, el id del .desktop y el nombre
// visible. Cada uno casa si es igual al appId, si es igual a su última parte
// (el appId suele llevar delante un dominio o un prefijo), si el appId
// empieza por él ("veadotube-mini" con "Veadotube.desktop") o si termina en
// él ("org.prismlauncher.PrismLauncher" con la clase "PrismLauncher").
function matchesAppId(entry, appId) {
    if (!entry)
        return false;
    var raw = typeof appId === "string" ? appId.trim() : "";
    if (raw.length === 0)
        return false;

    var id = compactId(raw);
    var tail = compactId(lastSegment(raw));
    var lower = raw.toLowerCase();
    if (id.length === 0)
        return false;

    var candidates = [entry.startupClass, entry.id, entry.name];
    for (var i = 0; i < candidates.length; ++i) {
        var key = compactId(candidates[i]);
        if (key.length === 0)
            continue;
        if (key === id || key === tail)
            return true;
        if (key.length >= 5 && bounded(lower, key, true))
            return true;
        if (key.length >= 5 && bounded(lower, key, false))
            return true;
    }
    return false;
}

// Candidatos de icono para una app, en orden de preferencia.
//
// Con entrada de .desktop manda su icono (puede ser una ruta absoluta a un
// PNG sin extensión, como los AppImage). Sin entrada se prueba el appId tal
// cual, porque los nombres de icono del tema distinguen mayúsculas:
// "org.prismlauncher.PrismLauncher" existe y "org.prismlauncher.prismlauncher"
// no.
function iconCandidates(entry, appId) {
    var result = [];
    var raw = typeof appId === "string" ? appId.trim() : "";

    function push(value) {
        if (!value)
            return;
        var text = String(value).trim();
        if (text.length === 0 || result.indexOf(text) !== -1)
            return;
        result.push(text);
    }

    if (entry && entry.icon)
        push(entry.icon);
    push(raw);
    if (entry && entry.startupClass)
        push(entry.startupClass);
    push(normalizeId(raw));

    return result;
}

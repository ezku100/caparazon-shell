.pragma library

// Resolución de la carátula de una pista MPRIS.
//
// Casi todos los reproductores mandan la carátula en mpris:artUrl, pero los
// navegadores no la mandan cuando suena un vídeo de YouTube: sólo publican
// xesam:url. En ese caso la carátula sale de la miniatura del vídeo
// (i.ytimg.com), que existe para todos los vídeos.
//
// La lógica vive aquí y no dentro del QML para poder comprobarla con node.

// Normaliza la URL de la carátula: Image necesita un esquema, así que una
// ruta local se convierte en file://.
function normalizeArt(url) {
    const value = String(url || "").trim();
    if (value === "")
        return "";
    return value.indexOf("/") === 0 ? "file://" + value : value;
}

// ID del vídeo a partir de la URL de la página (xesam:url).
function ytIdFromPage(url) {
    const match = /(?:youtube\.com\/watch\?(?:[^#]*&)?v=|youtu\.be\/|youtube\.com\/(?:shorts|embed|live)\/)([A-Za-z0-9_-]{11})/
        .exec(String(url || ""));
    return match ? match[1] : "";
}

// ID del vídeo a partir de la URL de la miniatura (i.ytimg.com/vi/ID/...).
function ytIdFromArt(url) {
    const match = /(?:i\.ytimg\.com|img\.youtube\.com)\/vi(?:_webp)?\/([A-Za-z0-9_-]{11})\//
        .exec(String(url || ""));
    return match ? match[1] : "";
}

// Miniaturas de un vídeo, de mejor a peor. maxresdefault (1280x720) sólo
// existe en los vídeos en HD; mqdefault (320x180, 16:9 sin barras) siempre.
function ytThumbnails(id) {
    const key = String(id || "").trim();
    if (!/^[A-Za-z0-9_-]{11}$/.test(key))
        return [];
    return [
        "https://i.ytimg.com/vi/" + key + "/maxresdefault.jpg",
        "https://i.ytimg.com/vi/" + key + "/mqdefault.jpg"
    ];
}

// Carátulas candidatas de un reproductor: primero la que manda y, si no hay
// o si el reproductor es un navegador con YouTube, la miniatura del vídeo.
function artCandidates(player) {
    const list = [];
    if (!player)
        return list;

    const direct = normalizeArt(player.trackArtUrl);
    if (direct !== "")
        list.push(direct);

    const meta = player.metadata || {};
    const ids = [ytIdFromArt(direct), ytIdFromPage(meta["xesam:url"])];
    for (let i = 0; i < ids.length; ++i) {
        if (ids[i] === "")
            continue;
        const thumbs = ytThumbnails(ids[i]);
        for (let j = 0; j < thumbs.length; ++j) {
            if (list.indexOf(thumbs[j]) === -1)
                list.push(thumbs[j]);
        }
    }
    return list;
}

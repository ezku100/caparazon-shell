// Escenarios de la resolución de carátulas MPRIS.
//
// La lógica vive en modules/music/ArtUrls.js, que QML carga como JavaScript.
// Aquí se ejecuta ese mismo archivo con node (sin la directiva .pragma library,
// que sólo entiende QML) para comprobar cómo se saca la carátula cuando el
// reproductor no manda mpris:artUrl, como pasa con YouTube en el navegador.
//
// Salida por stdout: una línea por escenario, "id\tPASS|FAIL\tdetalle".

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "music", "ArtUrls.js");

const source = fs
    .readFileSync(modulePath, "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(source, context, { filename: "ArtUrls.js" });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const { normalizeArt, ytIdFromPage, ytIdFromArt, ytThumbnails, artCandidates } = context;

const VIDEO_ID = "PtKrNXl93FU";

// Reproductor como el de Zen/Firefox con YouTube: sin carátula, con la URL
// del vídeo en xesam:url.
const ZEN_PLAYER = {
    trackArtUrl: "",
    metadata: {
        "mpris:trackid": "/org/mpris/MediaPlayer2/firefox",
        "xesam:album": "",
        "xesam:artist": [""],
        "xesam:title": "Revisando Vídeos - YouTube",
        "xesam:url": `https://www.youtube.com/watch?v=${VIDEO_ID}`,
    },
};

const cases = [
    {
        id: "normalize-vacia",
        detail: "sin URL no hay carátula",
        run: () => normalizeArt(""),
        expected: "",
    },
    {
        id: "normalize-espacios",
        detail: "la URL se recorta antes de usarla",
        run: () => normalizeArt("   "),
        expected: "",
    },
    {
        id: "normalize-ruta",
        detail: "una ruta local necesita el esquema file:",
        run: () => normalizeArt("/home/ezku/caratula.png"),
        expected: "file:///home/ezku/caratula.png",
    },
    {
        id: "normalize-url",
        detail: "una URL con esquema no se toca",
        run: () => normalizeArt("https://i.ytimg.com/vi/abc/hqdefault.jpg"),
        expected: "https://i.ytimg.com/vi/abc/hqdefault.jpg",
    },
    {
        id: "id-watch",
        detail: "el ID sale de una URL de watch de YouTube",
        run: () => ytIdFromPage(`https://www.youtube.com/watch?v=${VIDEO_ID}`),
        expected: VIDEO_ID,
    },
    {
        id: "id-watch-parametros",
        detail: "el ID se busca aunque la URL tenga más parámetros antes",
        run: () => ytIdFromPage(`https://www.youtube.com/watch?list=PL123&v=${VIDEO_ID}&t=10`),
        expected: VIDEO_ID,
    },
    {
        id: "id-watch-musica",
        detail: "YouTube Music también vale",
        run: () => ytIdFromPage(`https://music.youtube.com/watch?v=${VIDEO_ID}`),
        expected: VIDEO_ID,
    },
    {
        id: "id-youtu-be",
        detail: "el ID sale de un enlace corto de YouTube",
        run: () => ytIdFromPage(`https://youtu.be/${VIDEO_ID}?t=42`),
        expected: VIDEO_ID,
    },
    {
        id: "id-shorts",
        detail: "el ID sale de un Short",
        run: () => ytIdFromPage(`https://www.youtube.com/shorts/${VIDEO_ID}`),
        expected: VIDEO_ID,
    },
    {
        id: "id-embed",
        detail: "el ID sale de un vídeo incrustado",
        run: () => ytIdFromPage(`https://www.youtube.com/embed/${VIDEO_ID}`),
        expected: VIDEO_ID,
    },
    {
        id: "id-otro-sitio",
        detail: "una página que no es de YouTube no da ningún ID",
        run: () => ytIdFromPage(`https://example.com/watch?v=${VIDEO_ID}`),
        expected: "",
    },
    {
        id: "id-caratula",
        detail: "el ID sale de la URL de la miniatura",
        run: () => ytIdFromArt(`https://i.ytimg.com/vi/${VIDEO_ID}/hqdefault.jpg`),
        expected: VIDEO_ID,
    },
    {
        id: "id-caratula-webp",
        detail: "también con la variante webp de las miniaturas",
        run: () => ytIdFromArt(`https://i.ytimg.com/vi_webp/${VIDEO_ID}/hqdefault.webp`),
        expected: VIDEO_ID,
    },
    {
        id: "miniaturas",
        detail: "la miniatura grande va primero y la pequeña hace de respaldo",
        run: () => ytThumbnails(VIDEO_ID).join("|"),
        expected: `https://i.ytimg.com/vi/${VIDEO_ID}/maxresdefault.jpg|https://i.ytimg.com/vi/${VIDEO_ID}/mqdefault.jpg`,
    },
    {
        id: "miniaturas-invalidas",
        detail: "un ID que no es de YouTube no tiene miniaturas",
        run: () => ytThumbnails("corto").length,
        expected: 0,
    },
    {
        id: "candidatas-directa",
        detail: "la carátula que manda el reproductor es la primera",
        run: () => artCandidates({ trackArtUrl: "https://ejemplo/caratula.png", metadata: {} }).join("|"),
        expected: "https://ejemplo/caratula.png",
    },
    {
        id: "candidatas-youtube",
        detail: "sin mpris:artUrl se sacan las miniaturas del vídeo de YouTube",
        run: () => artCandidates(ZEN_PLAYER).join("|"),
        expected: `https://i.ytimg.com/vi/${VIDEO_ID}/maxresdefault.jpg|https://i.ytimg.com/vi/${VIDEO_ID}/mqdefault.jpg`,
    },
    {
        id: "candidatas-vacias",
        detail: "un reproductor sin carátula ni URL no da candidatas",
        run: () => artCandidates({ trackArtUrl: "", metadata: {} }).length,
        expected: 0,
    },
    {
        id: "candidatas-sin-repetir",
        detail: "la misma miniatura no se repite",
        run: () => {
            const list = artCandidates({
                trackArtUrl: `https://i.ytimg.com/vi/${VIDEO_ID}/hqdefault.jpg`,
                metadata: { "xesam:url": `https://www.youtube.com/watch?v=${VIDEO_ID}` },
            });
            return new Set(list).size === list.length ? "sin repetir" : "repetida";
        },
        expected: "sin repetir",
    },
];

const lines = [];
for (const item of cases) {
    let value;
    try {
        value = item.run();
    } catch (error) {
        value = `error: ${error.message}`;
    }
    const ok = value === item.expected;
    lines.push(`${item.id}\t${ok ? "PASS" : "FAIL"}\t${item.detail} (esperado ${item.expected}, obtenido ${value})`);
}

process.stdout.write(lines.join("\n"));

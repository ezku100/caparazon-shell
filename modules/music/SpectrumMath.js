.pragma library

// Lógica del espectro de audio del modo compacto de Música.
//
// El espectro viene de cava: el sampler (modules/music/spectrumfeed.py,
// adaptado del wavefeed.py del plugin de Noctalia) publica 32 bytes por
// frame en waves.json. Aquí se traducen a niveles 0..1, se suavizan para que
// no parpadeen y se interpolan los colores del tema a lo ancho.
//
// Es JavaScript puro a propósito: se puede probar con node sin levantar la
// shell (tests/support/spectrum_math_harness.js).

// Número de barras del espectro, el mismo que pide cava.
var BARS = 32;

// Cuánto se acerca cada barra a su objetivo en cada frame: 0 es congelado
// y 1 es sin suavizado.
var FACTOR = 0.45;

// Un byte de cava (0..255) como nivel 0..1. Lo que no sea un número vale 0
// y lo que se salga del rango se recorta.
function levelFromByte(value) {
    var level = Number(value);
    if (!isFinite(level))
        return 0;
    if (level < 0)
        level = 0;
    if (level > 255)
        level = 255;
    return level / 255;
}

// Un paso de suavizado: se mueve una fracción del camino que falta.
function smooth(current, target, factor) {
    var from = Number(current);
    var to = Number(target);
    if (!isFinite(from))
        from = 0;
    if (!isFinite(to))
        to = 0;
    return from + (to - from) * factor;
}

// El espectro puede llegar como array de JavaScript (en node) o como la lista
// que QML expone para un `property var` del JsonAdapter: esa lista tiene
// length y se indexa igual, pero `Array.isArray()` devuelve false y el
// suavizado se quedaba sin datos (barras planas). Por eso se acepta
// cualquier colección con length numérico.
function asLevels(source) {
    if (source === null || source === undefined)
        return [];
    if (typeof source === "string")
        return [];

    var length = Number(source.length);
    if (!isFinite(length) || length <= 0)
        return [];

    var values = [];
    for (var i = 0; i < Math.floor(length); ++i)
        values.push(source[i]);

    return values;
}

// Los niveles del siguiente frame. `spec` son los bytes que publica el
// sampler, `previous` los niveles del frame anterior. Sin reproducción el
// objetivo es cero, así que las barras decaen en vez de quedarse congeladas.
function nextLevels(spec, previous, playing, barCount, factor) {
    var count = Number(barCount);
    if (!isFinite(count) || count <= 0)
        count = BARS;
    count = Math.floor(count);

    var step = Number(factor);
    if (!isFinite(step) || step <= 0 || step > 1)
        step = FACTOR;

    var source = asLevels(spec);
    var before = asLevels(previous);
    var levels = [];

    for (var i = 0; i < count; ++i) {
        var target = 0;
        if (playing && i < source.length)
            target = levelFromByte(source[i]);
        levels.push(smooth(before[i], target, step));
    }

    return levels;
}

// Interpola dos colores para el degradado del espectro. `index` es la barra
// y `count` cuántas hay; con una sola barra sale el color de partida.
function mixColor(from, to, index, count) {
    var start = from || { r: 0, g: 0, b: 0, a: 1 };
    var end = to || { r: 0, g: 0, b: 0, a: 1 };

    var total = Number(count);
    var position = Number(index);
    if (!isFinite(total) || total <= 1)
        position = 0;
    else if (!isFinite(position) || position < 0)
        position = 0;
    else if (position > total - 1)
        position = total - 1;

    var ratio = total > 1 ? position / (total - 1) : 0;

    return {
        r: start.r + (end.r - start.r) * ratio,
        g: start.g + (end.g - start.g) * ratio,
        b: start.b + (end.b - start.b) * ratio,
        a: start.a + (end.a - start.a) * ratio,
    };
}

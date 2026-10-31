// Escenarios de la lógica del espectro del modo compacto.
//
// La lógica vive en modules/music/SpectrumMath.js, que QML carga como
// JavaScript. Aquí se ejecuta ese mismo archivo con node (sin la directiva
// .pragma library, que sólo entiende QML) para comprobar el mapeo de bytes a
// niveles, el suavizado y el degradado del tema.
//
// Salida por stdout: una línea por escenario, "id\tPASS|FAIL\tdetalle".

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "music", "SpectrumMath.js");

const source = fs
    .readFileSync(modulePath, "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(source, context, { filename: "SpectrumMath.js" });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const {
    BARS,
    FACTOR,
    levelFromByte,
    smooth,
    nextLevels,
    mixColor,
} = context;

// Redondea para comparar floats sin que 0.4500000000000001 rompa el caso.
function rounded(value) {
    return Number(Number(value).toFixed(6));
}

function roundedColor(color) {
    return JSON.stringify({
        r: rounded(color.r),
        g: rounded(color.g),
        b: rounded(color.b),
        a: rounded(color.a),
    });
}

const PRIMARY = { r: 0.2, g: 0.4, b: 0.6, a: 1 };
const TERTIARY = { r: 0.8, g: 0.6, b: 0.4, a: 1 };

const cases = [
    {
        id: "byte-zero",
        detail: "un byte a cero es nivel cero",
        run: () => levelFromByte(0),
        expected: 0,
    },
    {
        id: "byte-full",
        detail: "un byte a 255 es nivel uno",
        run: () => levelFromByte(255),
        expected: 1,
    },
    {
        id: "byte-mid",
        detail: "un byte intermedio se divide entre 255",
        run: () => rounded(levelFromByte(128)),
        expected: rounded(128 / 255),
    },
    {
        id: "byte-text",
        detail: "una basura no es un nivel",
        run: () => levelFromByte("basura"),
        expected: 0,
    },
    {
        id: "byte-negative-clamped",
        detail: "un byte negativo se recorta a cero",
        run: () => levelFromByte(-5),
        expected: 0,
    },
    {
        id: "byte-over-clamped",
        detail: "un byte por encima de 255 se recorta a uno",
        run: () => levelFromByte(999),
        expected: 1,
    },
    {
        id: "smooth-half",
        detail: "suavizar desde cero con factor 0.45 da 0.45",
        run: () => rounded(smooth(0, 1, 0.45)),
        expected: 0.45,
    },
    {
        id: "smooth-keeps",
        detail: "suavizar un valor consigo mismo no lo mueve",
        run: () => rounded(smooth(0.5, 0.5, 0.45)),
        expected: 0.5,
    },
    {
        id: "levels-length",
        detail: "siempre hay tantas barras como se piden",
        run: () => nextLevels([], [], true, 32, 0.45).length,
        expected: 32,
    },
    {
        id: "levels-empty-is-zero",
        detail: "sin espectro las barras están a cero",
        run: () => nextLevels([], [], true, 32, 0.45).every((v) => v === 0),
        expected: true,
    },
    {
        id: "levels-rises",
        detail: "una barra en alto sube desde cero hacia su valor",
        run: () => rounded(nextLevels([255, 255], [0, 0], true, 2, 0.45)[0]),
        expected: 0.45,
    },
    {
        id: "levels-decay-when-paused",
        detail: "en pausa las barras decaen hacia cero",
        run: () => nextLevels([], [1, 1], false, 2, 0.45).map((v) => rounded(v)).join("|"),
        expected: "0.55|0.55",
    },
    {
        id: "levels-short-spec",
        detail: "si faltan bytes, las barras sobrantes están a cero",
        run: () => nextLevels([255], [], true, 3, 0.45).map((v) => rounded(v)).join("|"),
        expected: "0.45|0|0",
    },
    {
        id: "levels-bad-factor",
        detail: "un factor inválido usa el de por defecto",
        run: () => rounded(nextLevels([255], [], true, 1, 0)[0]),
        expected: rounded(FACTOR),
    },
    {
        id: "levels-default-bars",
        detail: "sin número de barras se usan las del módulo",
        run: () => nextLevels([], [], true, 0, 0.45).length,
        expected: BARS,
    },
    {
        id: "levels-array-like-spec",
        detail: "una lista con length pero sin Array.isArray también vale (así llega de QML)",
        run: () => rounded(nextLevels({ 0: 255, 1: 255, length: 2 }, [0, 0], true, 2, 0.45)[0]),
        expected: 0.45,
    },
    {
        id: "levels-array-like-previous",
        detail: "los niveles previos también pueden llegar como lista de QML",
        run: () => nextLevels([], { 0: 1, 1: 1, length: 2 }, false, 2, 0.45).map((v) => rounded(v)).join("|"),
        expected: "0.55|0.55",
    },
    {
        id: "mix-starts-at-from",
        detail: "la primera barra es el color primario",
        run: () => roundedColor(mixColor(PRIMARY, TERTIARY, 0, 8)),
        expected: roundedColor(PRIMARY),
    },
    {
        id: "mix-ends-at-to",
        detail: "la última barra es el color terciario",
        run: () => roundedColor(mixColor(PRIMARY, TERTIARY, 7, 8)),
        expected: roundedColor(TERTIARY),
    },
    {
        id: "mix-single-count",
        detail: "con una sola barra no hay NaN",
        run: () => roundedColor(mixColor(PRIMARY, TERTIARY, 0, 1)),
        expected: roundedColor(PRIMARY),
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

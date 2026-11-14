// Escenarios de los estados de la barra dinámica.
//
// La lógica vive en modules/bar/BarSmartHide.js, que QML carga como
// JavaScript. Aquí se ejecuta ese mismo archivo con node para comprobar los
// estados y la zona clicable sin depender del compositor.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "bar", "BarSmartHide.js");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(fs.readFileSync(modulePath, "utf8"), context, {
        filename: "BarSmartHide.js",
    });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const stateFor = context.stateFor;
const maskRect = context.maskRect;
const exclusiveZone = context.exclusiveZone;

function same(left, right) {
    if (left === right) {
        return true;
    }
    if (typeof left !== "object" || typeof right !== "object") {
        return false;
    }
    if (left === null || right === null) {
        return false;
    }
    const keys = Object.keys(left);
    if (keys.length !== Object.keys(right).length) {
        return false;
    }
    return keys.every(function (key) {
        return Object.prototype.hasOwnProperty.call(right, key) && same(left[key], right[key]);
    });
}

// Barra arriba en un monitor de 1920x1080: la ventana ocupa todo el ancho y
// 40 px de barra más 12 de aire para la sombra.
const topMetrics = {
    position: "top",
    surfaceWidth: 1920,
    surfaceHeight: 52,
    barThickness: 40,
    shadowPad: 12,
    hotEdge: 6,
};
const bottomMetrics = Object.assign({}, topMetrics, { position: "bottom" });

// Columna en un monitor vertical de 1080x1920: la ventana mide 40 de barra
// más el aire de la sombra y todo el alto de la pantalla.
const leftMetrics = {
    position: "left",
    surfaceWidth: 52,
    surfaceHeight: 1920,
    barThickness: 40,
    shadowPad: 12,
    hotEdge: 6,
};
const rightMetrics = Object.assign({}, leftMetrics, { position: "right" });

const cases = [
    {
        id: "anclada",
        detail: "anclada se queda visible aunque no haya ratón",
        run: () => stateFor(true, false),
        expected: "anchored",
    },
    {
        id: "anclada-con-raton",
        detail: "anclada sigue igual con el ratón encima",
        run: () => stateFor(true, true),
        expected: "anchored",
    },
    {
        id: "dinamica-sin-raton",
        detail: "dinámica sin ratón se aparta al filo",
        run: () => stateFor(false, false),
        expected: "hidden",
    },
    {
        id: "dinamica-con-raton",
        detail: "dinámica con el ratón al filo se revela",
        run: () => stateFor(false, true),
        expected: "revealed",
    },
    {
        id: "mascara-oculta-arriba",
        detail: "oculta arriba, la franja sensible queda en el filo superior",
        run: () => maskRect("hidden", topMetrics),
        expected: { x: 0, y: 0, width: 1920, height: 6 },
    },
    {
        id: "mascara-oculta-abajo",
        detail: "oculta abajo, la franja sensible queda en el filo inferior",
        run: () => maskRect("hidden", bottomMetrics),
        expected: { x: 0, y: 46, width: 1920, height: 6 },
    },
    {
        id: "mascara-oculta-izquierda",
        detail: "oculta a la izquierda, la franja sensible queda en el filo",
        run: () => maskRect("hidden", leftMetrics),
        expected: { x: 0, y: 0, width: 6, height: 1920 },
    },
    {
        id: "mascara-oculta-derecha",
        detail: "oculta a la derecha, la franja sensible queda al otro filo",
        run: () => maskRect("hidden", rightMetrics),
        expected: { x: 46, y: 0, width: 6, height: 1920 },
    },
    {
        id: "mascara-arriba",
        detail: "arriba la barra acepta el cuerpo menos el aire de la sombra",
        run: () => maskRect("revealed", topMetrics),
        expected: { x: 12, y: 0, width: 1896, height: 40 },
    },
    {
        id: "mascara-abajo",
        detail: "abajo el cuerpo se pega al filo inferior",
        run: () => maskRect("revealed", bottomMetrics),
        expected: { x: 12, y: 12, width: 1896, height: 40 },
    },
    {
        id: "mascara-izquierda",
        detail: "a la izquierda el cuerpo ocupa el filo",
        run: () => maskRect("revealed", leftMetrics),
        expected: { x: 0, y: 0, width: 40, height: 1920 },
    },
    {
        id: "mascara-derecha",
        detail: "a la derecha la columna deja el aire de la sombra por dentro",
        run: () => maskRect("revealed", rightMetrics),
        expected: { x: 12, y: 0, width: 40, height: 1920 },
    },
    {
        id: "anclada-reserva-franja",
        detail: "anclada reserva su grosor en el compositor",
        run: () => exclusiveZone(true, 40),
        expected: 40,
    },
    {
        id: "dinamica-no-reserva",
        detail: "dinámica no reserva nada: las ventanas llegan al borde",
        run: () => exclusiveZone(false, 40),
        expected: 0,
    },
];

const results = {};
for (const item of cases) {
    let value;
    try {
        value = item.run();
    } catch (error) {
        value = `error: ${error.message}`;
    }
    results[item.id] = {
        ok: same(value, item.expected),
        expected: item.expected,
        value: value === undefined ? null : value,
        detail: item.detail,
    };
}

process.stdout.write(JSON.stringify(results));

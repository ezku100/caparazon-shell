// Escenarios de los estados del dock inteligente.
//
// La lógica vive en modules/dock/DockSmartHide.js, que QML carga como
// JavaScript. Aquí se ejecuta ese mismo archivo con node para comprobar los
// estados sin depender del compositor: mismo código, mismos casos.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "dock", "DockSmartHide.js");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(fs.readFileSync(modulePath, "utf8"), context, {
        filename: "DockSmartHide.js",
    });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const stateFor = context.stateFor;
const maskRect = context.maskRect;
const dockOffset = context.dockOffset;
const exclusiveZone = context.exclusiveZone;

// La superficie del dock mide dockHeight + shadowPad.
const metrics = {
    surfaceWidth: 1920,
    surfaceHeight: 64,
    dockLength: 360,
    dockThickness: 52,
    shadowPad: 12,
    position: "bottom",
    hotEdge: 6,
    bottomGap: 0,
};

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

// Mismas medidas con el dock pegado al borde superior: la franja sensible y
// el cuerpo quedan arriba y el aire de la sombra abajo.
const topMetrics = Object.assign({}, metrics, { position: "top" });

// Pantalla vertical (1080x1920) con el dock en un lado: la columna se centra
// a lo alto y la ventana es una franja de 64 px pegada al filo.
const leftMetrics = {
    surfaceWidth: 64,
    surfaceHeight: 1920,
    dockLength: 360,
    dockThickness: 52,
    shadowPad: 12,
    position: "left",
    hotEdge: 6,
    bottomGap: 0,
};
const rightMetrics = Object.assign({}, leftMetrics, { position: "right" });

const cases = [
    {
        id: "anclado",
        detail: "con el pin puesto, el dock se queda anclado aunque no haya ratón",
        run: () => stateFor(true, false),
        expected: "anchored",
    },
    {
        id: "anclado-con-raton",
        detail: "con el pin puesto sigue anclado aunque el ratón esté encima",
        run: () => stateFor(true, true),
        expected: "anchored",
    },
    {
        id: "oculto",
        detail: "sin pin y sin ratón, el dock se oculta",
        run: () => stateFor(false, false),
        expected: "hidden",
    },
    {
        id: "revelado",
        detail: "sin pin pero con el ratón encima, el dock se revela",
        run: () => stateFor(false, true),
        expected: "revealed",
    },
    {
        id: "mascara-anclada",
        detail: "anclado, la zona clicable es el dock entero",
        run: () => maskRect("anchored", metrics),
        expected: { x: 780, y: 12, width: 360, height: 52 },
    },
    {
        id: "mascara-oculta",
        detail: "apartado, sólo queda una franja en el borde inferior",
        run: () => maskRect("hidden", metrics),
        expected: { x: 780, y: 58, width: 360, height: 6 },
    },
    {
        id: "mascara-revelada",
        detail: "revelado, la zona clicable vuelve a ser el dock entero",
        run: () => maskRect("revealed", metrics),
        expected: { x: 780, y: 12, width: 360, height: 52 },
    },
    {
        id: "desplazamiento-oculto",
        detail: "apartado, el dock baja fuera de la pantalla",
        run: () => dockOffset("hidden", metrics),
        expected: 64,
    },
    {
        id: "desplazamiento-anclado",
        detail: "anclado, el dock no se desplaza",
        run: () => dockOffset("anchored", metrics),
        expected: 0,
    },
    {
        id: "zona-exclusiva-anclada",
        detail: "anclado, el dock reserva su franja",
        run: () => exclusiveZone(true, metrics),
        expected: 52,
    },
    {
        id: "zona-exclusiva-suelta",
        detail: "sin pin, el dock no reserva nada",
        run: () => exclusiveZone(false, metrics),
        expected: 0,
    },
    {
        id: "mascara-oculta-arriba",
        detail: "arriba y apartado, la franja sensible queda en el filo superior",
        run: () => maskRect("hidden", topMetrics),
        expected: { x: 780, y: 0, width: 360, height: 6 },
    },
    {
        id: "mascara-revelada-arriba",
        detail: "arriba y revelado, el cuerpo ocupa el filo superior",
        run: () => maskRect("revealed", topMetrics),
        expected: { x: 780, y: 0, width: 360, height: 52 },
    },
    {
        id: "mascara-oculta-izquierda",
        detail: "a la izquierda y apartado, la franja sensible queda en el filo",
        run: () => maskRect("hidden", leftMetrics),
        expected: { x: 0, y: 780, width: 6, height: 360 },
    },
    {
        id: "mascara-revelada-izquierda",
        detail: "a la izquierda y revelado, la columna ocupa el filo",
        run: () => maskRect("revealed", leftMetrics),
        expected: { x: 0, y: 780, width: 52, height: 360 },
    },
    {
        id: "mascara-revelada-derecha",
        detail: "a la derecha, la columna deja el aire de la sombra por dentro",
        run: () => maskRect("revealed", rightMetrics),
        expected: { x: 12, y: 780, width: 52, height: 360 },
    },
    {
        id: "mascara-oculta-derecha",
        detail: "a la derecha y apartado, la franja sensible queda al filo",
        run: () => maskRect("hidden", rightMetrics),
        expected: { x: 58, y: 780, width: 6, height: 360 },
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

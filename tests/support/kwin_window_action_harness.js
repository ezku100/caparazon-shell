// Escenarios de la acción de ventana del dock.
//
// La lógica vive en modules/bar/KWinWindowAction.js, que KWin carga como
// script. Aquí se ejecuta ese mismo archivo con node contra un `workspace`
// falso para comprobar las decisiones (restaurar, minimizar, enfocar) sin
// depender del compositor.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const scriptPath = path.join(repositoryRoot, "modules", "bar", "KWinWindowAction.js");

const source = fs.readFileSync(scriptPath, "utf8");

function makeWindow(spec) {
    const window = {
        desktopFileName: spec.desktopFileName || "",
        resourceClass: spec.resourceClass || "",
        resourceName: spec.resourceName || "",
        caption: spec.caption || "",
        minimized: spec.minimized === true,
        active: spec.active === true,
        normalWindow: spec.normalWindow !== false,
        skipTaskbar: spec.skipTaskbar === true,
        deleted: spec.deleted === true,
    };
    window.label = spec.label || window.desktopFileName || window.resourceClass;
    return window;
}

// Ejecuta el script de KWin con un workspace falso y devuelve lo que pasó.
function runScenario(scenario) {
    const windows = scenario.windows.map(makeWindow);
    const activated = [];
    const logs = [];

    const workspace = {};
    Object.defineProperty(workspace, "windowList", {
        value: () => windows,
        enumerable: true,
    });
    Object.defineProperty(workspace, "activeWindow", {
        get: () => windows.find((window) => window.active) || null,
        set: (value) => {
            activated.push(value);
        },
        enumerable: true,
    });

    const context = vm.createContext({
        workspace: workspace,
        console: {
            info: (message) => {
                logs.push(String(message));
            },
        },
    });

    const prepared = source
        .split("__TARGET__")
        .join(scenario.target)
        .split("__ACTIVE__")
        .join(scenario.activeHint || "");

    vm.runInContext(prepared, context, { filename: "KWinWindowAction.js" });

    const prefix = "CAPARAZON_WINDOW_ACTION:";
    const actionLine = logs.find((line) => line.includes(prefix));
    let action = null;
    if (actionLine) {
        action = JSON.parse(actionLine.slice(actionLine.indexOf(prefix) + prefix.length)).action;
    }

    return {
        action: action,
        minimized: windows.filter((window) => window.minimized).map((window) => window.label),
        activated: activated.map((window) => window.label),
    };
}

const cases = [
    {
        id: "la-app-enfocada-se-minimiza",
        detail: "el segundo clic sobre la app enfocada la minimiza",
        scenario: {
            target: "kitty",
            activeHint: "kitty",
            windows: [{ desktopFileName: "kitty", label: "kitty", active: true }],
        },
        expected: { action: "minimize", minimized: ["kitty"], activated: [] },
    },
    {
        id: "la-ventana-minimizada-se-restaura",
        detail: "una ventana escondida vuelve y se enfoca",
        scenario: {
            target: "app.zen_browser.zen",
            activeHint: "",
            windows: [{ desktopFileName: "app.zen_browser.zen", label: "zen", minimized: true }],
        },
        expected: { action: "restore", minimized: [], activated: ["zen"] },
    },
    {
        id: "la-app-en-segundo-plano-se-enfoca",
        detail: "una app que no está enfocada sólo se enfoca",
        scenario: {
            target: "discord",
            activeHint: "kitty",
            windows: [
                { desktopFileName: "kitty", label: "kitty", active: true },
                { desktopFileName: "discord", label: "discord" },
            ],
        },
        expected: { action: "focus", minimized: [], activated: ["discord"] },
    },
    {
        id: "la-pista-de-la-shell-minimiza",
        detail: "si el clic robó el foco, la pista de la shell decide minimizar",
        scenario: {
            target: "discord",
            activeHint: "discord",
            windows: [
                { desktopFileName: "kitty", label: "kitty", active: true },
                { desktopFileName: "discord", label: "discord" },
            ],
        },
        expected: { action: "minimize", minimized: ["discord"], activated: [] },
    },
    {
        id: "sin-ventanas-no-pasa-nada",
        detail: "una app sin ventanas no se toca",
        scenario: {
            target: "nada",
            activeHint: "",
            windows: [{ desktopFileName: "kitty", label: "kitty", active: true }],
        },
        expected: { action: "none", minimized: [], activated: [] },
    },
    {
        id: "con-varias-ventanas-se-minimiza-la-activa",
        detail: "de una app con varias ventanas se minimiza la enfocada",
        scenario: {
            target: "app.zen_browser.zen",
            activeHint: "app.zen_browser.zen",
            windows: [
                { desktopFileName: "app.zen_browser.zen", label: "zen-1" },
                { desktopFileName: "app.zen_browser.zen", label: "zen-2", active: true },
            ],
        },
        expected: { action: "minimize", minimized: ["zen-2"], activated: [] },
    },
    {
        id: "las-ventanas-del-propio-shell-se-ignoran",
        detail: "los paneles de la shell no son ventanas de app",
        scenario: {
            target: "quickshell",
            activeHint: "",
            windows: [{ desktopFileName: "quickshell", label: "panel", skipTaskbar: true }],
        },
        expected: { action: "none", minimized: [], activated: [] },
    },
    {
        id: "la-clase-de-arranque-sirve-de-appid",
        detail: "una ventana sin .desktop se empareja por su clase",
        scenario: {
            target: "prismlauncher",
            activeHint: "",
            windows: [{ resourceClass: "PrismLauncher", label: "prism" }],
        },
        expected: { action: "focus", minimized: [], activated: ["prism"] },
    },
    {
        id: "los-candidatos-cubren-el-appid",
        detail: "con varios candidatos se encuentra la ventana por cualquiera de ellos",
        scenario: {
            target: "limusic|limusic-app",
            activeHint: "",
            windows: [{ desktopFileName: "limusic-app", label: "limusic" }],
        },
        expected: { action: "focus", minimized: [], activated: ["limusic"] },
    },
    {
        id: "el-appid-de-la-ventana-es-un-candidato",
        detail: "el .desktop y el appId de la ventana son el mismo nombre",
        scenario: {
            target: "app.zen_browser.zen|zen_browser",
            activeHint: "",
            windows: [{ desktopFileName: "app.zen_browser.zen", label: "zen" }],
        },
        expected: { action: "focus", minimized: [], activated: ["zen"] },
    },
    {
        id: "la-pista-usa-los-candidatos",
        detail: "la app activa se detecta aunque su nombre sea otro candidato",
        scenario: {
            target: "limusic|limusic-app",
            activeHint: "limusic-app",
            windows: [{ desktopFileName: "limusic-app", label: "limusic" }],
        },
        expected: { action: "minimize", minimized: ["limusic"], activated: [] },
    },
];

const results = {};
for (const item of cases) {
    let value;
    try {
        const outcome = runScenario(item.scenario);
        value = {
            action: outcome.action,
            minimized: outcome.minimized,
            activated: outcome.activated,
        };
    } catch (error) {
        value = `error: ${error.message}`;
    }
    results[item.id] = {
        ok: JSON.stringify(value) === JSON.stringify(item.expected),
        expected: item.expected,
        value: value,
        detail: item.detail,
    };
}

process.stdout.write(JSON.stringify(results));

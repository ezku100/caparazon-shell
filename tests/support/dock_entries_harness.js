// Escenarios del emparejamiento entre una ventana y su .desktop.
//
// La lógica vive en modules/dock/DockEntries.js, que QML carga como
// JavaScript. Aquí se ejecuta ese mismo archivo con node para comprobar el
// emparejamiento sin depender del compositor: mismo código, mismos casos.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "dock", "DockEntries.js");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(fs.readFileSync(modulePath, "utf8"), context, {
        filename: "DockEntries.js",
    });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const normalizeId = context.normalizeId;
const matchesAppId = context.matchesAppId;
const iconCandidates = context.iconCandidates;

const prismEntry = {
    id: "prism_launcher",
    name: "Prism Launcher",
    startupClass: "PrismLauncher",
    icon: "/home/ezku/AppImages/.icons/prism_launcher",
};

const cases = [
    {
        id: "prism-por-clase-de-arranque",
        detail: "org.prismlauncher.PrismLauncher debe casar con prism_launcher",
        run: () => matchesAppId(prismEntry, "org.prismlauncher.PrismLauncher"),
        expected: true,
    },
    {
        id: "prism-por-id-compacto",
        detail: "los separadores no deben impedir el match",
        run: () => matchesAppId({ id: "prism_launcher" }, "org.prismlauncher.prismlauncher"),
        expected: true,
    },
    {
        id: "prefijo-historico",
        detail: "veadotube-mini con .desktop Veadotube.desktop sigue casando",
        run: () => matchesAppId(
            { id: "Veadotube.desktop", startupClass: "veadotube" },
            "veadotube-mini",
        ),
        expected: true,
    },
    {
        id: "app-distinta",
        detail: "una app que no tiene nada que ver no debe casar",
        run: () => matchesAppId(
            { id: "firefox.desktop", startupClass: "firefox", name: "Firefox" },
            "org.prismlauncher.PrismLauncher",
        ),
        expected: false,
    },
    {
        id: "app-id-vacio",
        detail: "un appId vacío no casa con nada",
        run: () => matchesAppId(prismEntry, ""),
        expected: false,
    },
    {
        id: "icon-con-entrada",
        detail: "con entrada, manda su icono",
        run: () => iconCandidates(prismEntry, "org.prismlauncher.PrismLauncher")[0],
        expected: "/home/ezku/AppImages/.icons/prism_launcher",
    },
    {
        id: "icon-sin-entrada",
        detail: "sin entrada, se prueba el appId tal cual (el tema distingue mayúsculas)",
        run: () => iconCandidates(null, "org.prismlauncher.PrismLauncher")[0],
        expected: "org.prismlauncher.PrismLauncher",
    },
    {
        id: "normalize-id",
        detail: "normalizeId quita el sufijo .desktop y pasa a minúsculas",
        run: () => normalizeId("Prism_Launcher.desktop"),
        expected: "prism_launcher",
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
        ok: value === item.expected,
        expected: item.expected,
        value: value,
        detail: item.detail,
    };
}

process.stdout.write(JSON.stringify(results));

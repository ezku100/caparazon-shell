// Escenarios del contrato de los iconos de la barra.
//
// El modulo vive en modules/icons/BarIcons.js, que QML carga como JavaScript.
// Aqui se ejecuta ese mismo archivo con node para comprobar que cadenas de
// nombres de icono devuelve cada estado de la barra, y que esas cadenas
// resuelven en todos los temas de iconos instalados.
//
// La tabla AVAILABLE es el resultado de comprobar los temas en disco el
// 2026-10-28 (nombre exacto o -symbolic, respetando la herencia de cada
// index.theme). Si un nombre cambia, el test lo avisa antes que el usuario.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "icons", "BarIcons.js");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(fs.readFileSync(modulePath, "utf8"), context, {
        filename: "BarIcons.js",
    });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const sessionNames = context.sessionNames;
const powerButtonNames = context.powerButtonNames;
const volumeNames = context.volumeNames;
const powerProfileNames = context.powerProfileNames;

const THEMES = [
    "tela-dark",
    "colloid-dark",
    "reversal-dark",
    "breeze",
    "breeze-dark",
    "adwaita",
    "papirus",
];

const EVERYWHERE = [0, 1, 2, 3, 4, 5, 6];

const AVAILABLE = {
    "system-lock-screen": EVERYWHERE,
    "system-log-out": EVERYWHERE,
    "application-exit": EVERYWHERE,
    "system-shutdown": EVERYWHERE,
    "system-reboot": EVERYWHERE,
    "preferences-system-power": [0, 1, 2, 6],
    "audio-input-microphone": EVERYWHERE,
    "microphone-sensitivity-medium": EVERYWHERE,
    "microphone-sensitivity-muted": EVERYWHERE,
    "mic-off": [0, 1, 3, 4, 6],
    "microphone": [1, 2, 3, 4, 5],
    "audio-volume-high": EVERYWHERE,
    "audio-volume-medium": EVERYWHERE,
    "audio-volume-low": EVERYWHERE,
    "audio-volume-muted": EVERYWHERE,
    "power-profile-power-saver-symbolic": [0, 1, 2, 5, 6],
    "power-profile-balanced-symbolic": [0, 1, 2, 5, 6],
    "power-profile-performance-symbolic": [0, 1, 2, 5, 6],
    "battery-profile-powersave": [0, 1, 2, 3, 4, 6],
    "battery-profile-balanced": [3, 4, 6],
    "battery-profile-performance": [0, 1, 2, 3, 4, 6],
    "battery-low": EVERYWHERE,
};

// Todos los estados que la barra puede pedir.
const SCENES = {
    session_lock: () => sessionNames("lock"),
    session_logout: () => sessionNames("logout"),
    session_shutdown: () => sessionNames("shutdown"),
    session_reboot: () => sessionNames("reboot"),
    session_unknown: () => sessionNames("hibernate"),
    power_button: () => powerButtonNames(),
    speaker_high: () => volumeNames(false, 1.0, false),
    speaker_medium: () => volumeNames(false, 0.5, false),
    speaker_low: () => volumeNames(false, 0.2, false),
    speaker_muted: () => volumeNames(true, 0.8, false),
    speaker_silenced_by_level: () => volumeNames(false, 0.0005, false),
    microphone_on: () => volumeNames(false, 0.8, true),
    microphone_muted: () => volumeNames(true, 0.8, true),
    profile_saver: () => powerProfileNames("power-saver"),
    profile_balanced: () => powerProfileNames("balanced"),
    profile_performance: () => powerProfileNames("performance"),
    profile_unknown: () => powerProfileNames("turbo"),
};

function check(ok, detail) {
    return { ok: ok, detail: detail };
}

function sameList(values, expected) {
    return Array.isArray(values) && values.join("\u0000") === expected.join("\u0000");
}

function sameListDetail(values, expected) {
    return `esperado [${expected.join(", ")}], obtenido [${String(values)}]`;
}

function first(values) {
    return Array.isArray(values) && values.length > 0 ? values[0] : "";
}

function chainResolvesInTheme(names, themeIndex) {
    if (!Array.isArray(names))
        return false;
    return names.some((name) => {
        const themes = AVAILABLE[name];
        return Array.isArray(themes) && themes.indexOf(themeIndex) !== -1;
    });
}

const cases = [
    {
        id: "session_lock",
        name: "Bloquear usa el icono de bloqueo del tema",
        run: () => sessionNames("lock"),
        expect: (value) =>
            check(
                sameList(value, ["system-lock-screen"]),
                sameListDetail(value, ["system-lock-screen"]),
            ),
    },
    {
        id: "session_logout",
        name: "Cerrar sesion tiene alternativa si el tema no trae el icono",
        run: () => sessionNames("logout"),
        expect: (value) =>
            check(
                sameList(value, ["system-log-out", "application-exit"]),
                sameListDetail(value, ["system-log-out", "application-exit"]),
            ),
    },
    {
        id: "session_shutdown",
        name: "Apagar usa el icono de apagado del tema",
        run: () => sessionNames("shutdown"),
        expect: (value) =>
            check(
                sameList(value, ["system-shutdown"]),
                sameListDetail(value, ["system-shutdown"]),
            ),
    },
    {
        id: "session_reboot",
        name: "Reiniciar usa el icono de reinicio del tema",
        run: () => sessionNames("reboot"),
        expect: (value) =>
            check(
                sameList(value, ["system-reboot"]),
                sameListDetail(value, ["system-reboot"]),
            ),
    },
    {
        id: "session_unknown_is_empty",
        name: "Una accion desconocida no inventa icono",
        run: () => sessionNames("hibernate"),
        expect: (value) => check(sameList(value, []), String(value)),
    },
    {
        id: "power_button",
        name: "El boton de energia usa el simbolo de apagado",
        run: () => powerButtonNames(),
        expect: (value) =>
            check(
                first(value) === "system-shutdown" &&
                    value.indexOf("preferences-system-power") !== -1,
                `obtenido [${String(value)}]`,
            ),
    },
    {
        id: "speaker_high",
        name: "Altavoz alto por encima del 75 por ciento",
        run: () => volumeNames(false, 1.0, false),
        expect: (value) =>
            check(
                sameList(value, ["audio-volume-high"]),
                sameListDetail(value, ["audio-volume-high"]),
            ),
    },
    {
        id: "speaker_medium",
        name: "Altavoz medio entre 40 y 75 por ciento",
        run: () => volumeNames(false, 0.5, false),
        expect: (value) =>
            check(
                sameList(value, ["audio-volume-medium"]),
                sameListDetail(value, ["audio-volume-medium"]),
            ),
    },
    {
        id: "speaker_low",
        name: "Altavoz bajo por debajo del 40 por ciento",
        run: () => volumeNames(false, 0.2, false),
        expect: (value) =>
            check(
                sameList(value, ["audio-volume-low"]),
                sameListDetail(value, ["audio-volume-low"]),
            ),
    },
    {
        id: "speaker_muted",
        name: "Silenciado gana al nivel",
        run: () => volumeNames(true, 0.8, false),
        expect: (value) =>
            check(
                sameList(value, ["audio-volume-muted"]),
                sameListDetail(value, ["audio-volume-muted"]),
            ),
    },
    {
        id: "speaker_silenced_by_level",
        name: "Un nivel practicamente cero cuenta como silenciado",
        run: () => volumeNames(false, 0.0005, false),
        expect: (value) =>
            check(
                sameList(value, ["audio-volume-muted"]),
                sameListDetail(value, ["audio-volume-muted"]),
            ),
    },
    {
        id: "speaker_threshold_low_high",
        name: "El limite del 40 por ciento ya es medio",
        run: () => volumeNames(false, 0.40, false),
        expect: (value) =>
            check(
                sameList(value, ["audio-volume-medium"]),
                sameListDetail(value, ["audio-volume-medium"]),
            ),
    },
    {
        id: "speaker_threshold_medium_high",
        name: "El limite del 75 por ciento ya es alto",
        run: () => volumeNames(false, 0.75, false),
        expect: (value) =>
            check(
                sameList(value, ["audio-volume-high"]),
                sameListDetail(value, ["audio-volume-high"]),
            ),
    },
    {
        id: "microphone_on",
        name: "Microfono activo usa el icono de microfono",
        run: () => volumeNames(false, 0.8, true),
        expect: (value) =>
            check(
                first(value) === "audio-input-microphone" &&
                    value.indexOf("microphone-sensitivity-medium") !== -1,
                `obtenido [${String(value)}]`,
            ),
    },
    {
        id: "microphone_muted",
        name: "Microfono silenciado tiene su propio icono",
        run: () => volumeNames(true, 0.8, true),
        expect: (value) =>
            check(
                first(value) === "microphone-sensitivity-muted" &&
                    value.indexOf("mic-off") !== -1,
                `obtenido [${String(value)}]`,
            ),
    },
    {
        id: "microphone_silenced_by_level",
        name: "Un microfono a cero tambien sale silenciado",
        run: () => volumeNames(false, 0.0, true),
        expect: (value) =>
            check(
                first(value) === "microphone-sensitivity-muted",
                `obtenido [${String(value)}]`,
            ),
    },
    {
        id: "profile_saver",
        name: "Ahorro usa el perfil de energia del tema",
        run: () => powerProfileNames("power-saver"),
        expect: (value) =>
            check(
                first(value) === "power-profile-power-saver-symbolic" &&
                    value.indexOf("battery-profile-powersave") !== -1,
                `obtenido [${String(value)}]`,
            ),
    },
    {
        id: "profile_balanced",
        name: "Equilibrado usa el perfil del tema y conserva la alternativa",
        run: () => powerProfileNames("balanced"),
        expect: (value) =>
            check(
                first(value) === "power-profile-balanced-symbolic" &&
                    value.indexOf("battery-profile-balanced") !== -1,
                `obtenido [${String(value)}]`,
            ),
    },
    {
        id: "profile_performance",
        name: "Rendimiento usa el perfil del tema",
        run: () => powerProfileNames("performance"),
        expect: (value) =>
            check(
                first(value) === "power-profile-performance-symbolic" &&
                    value.indexOf("battery-profile-performance") !== -1,
                `obtenido [${String(value)}]`,
            ),
    },
    {
        id: "profile_unknown_is_balanced",
        name: "Un perfil desconocido se dibuja como equilibrado",
        run: () => powerProfileNames("turbo"),
        expect: (value) =>
            check(
                sameList(value, powerProfileNames("balanced")),
                `obtenido [${String(value)}]`,
            ),
    },
    {
        id: "every_chain_is_not_empty",
        name: "Ningun estado se queda sin icono",
        run: () =>
            Object.keys(SCENES)
                .filter((id) => id !== "session_unknown")
                .map((id) => `${id}=[${String(SCENES[id]())}]`),
        expect: (value) => {
            const empty = value.filter((item) => item.endsWith("=[]"));
            return check(empty.length === 0, empty.length === 0 ? "todas con nombres" : empty.join(" "));
        },
    },
    {
        id: "every_chain_name_is_known",
        name: "Ningun nombre esta mal escrito",
        run: () => {
            const unknown = [];
            Object.keys(SCENES).forEach((id) => {
                const names = SCENES[id]();
                names.forEach((name) => {
                    if (!AVAILABLE[name])
                        unknown.push(`${id}:${name}`);
                });
            });
            return unknown;
        },
        expect: (value) =>
            check(value.length === 0, value.length === 0 ? "todos conocidos" : value.join(" ")),
    },
    {
        id: "every_chain_resolves_in_every_theme",
        name: "Cada cadena tiene al menos un nombre en cada tema instalado",
        run: () => {
            const broken = [];
            Object.keys(SCENES).forEach((id) => {
                const names = SCENES[id]();
                if (names.length === 0)
                    return;
                THEMES.forEach((theme, index) => {
                    if (!chainResolvesInTheme(names, index))
                        broken.push(`${id}@${theme}`);
                });
            });
            return broken;
        },
        expect: (value) =>
            check(value.length === 0, value.length === 0 ? "resuelve en todos" : value.join(" ")),
    },
    {
        id: "every_chain_is_a_copy",
        name: "El QML no puede modificar la tabla del modulo",
        run: () => {
            const first1 = sessionNames("lock");
            first1.push("mutado");
            const second = sessionNames("lock");
            return second.join(",");
        },
        expect: (value) => check(value === "system-lock-screen", String(value)),
    },
];

const results = cases.map((item) => {
    try {
        const outcome = item.expect(item.run());
        return {
            id: item.id,
            name: item.name,
            ok: outcome.ok,
            detail: outcome.detail,
        };
    } catch (error) {
        return {
            id: item.id,
            name: item.name,
            ok: false,
            detail: `error: ${error.message}`,
        };
    }
});

process.stdout.write(`${JSON.stringify({ cases: results }, null, 2)}\n`);

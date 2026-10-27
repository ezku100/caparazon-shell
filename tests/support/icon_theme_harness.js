// Escenarios del contrato del tema de iconos.
//
// El módulo vive en modules/icons/IconTheme.js, que QML carga como
// JavaScript. Aquí se ejecuta ese mismo archivo con node para comprobar qué
// tema lee de kdeglobals, cuándo hay que reiniciar la shell y cómo se
// construye el comando de reinicio.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "icons", "IconTheme.js");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(fs.readFileSync(modulePath, "utf8"), context, {
        filename: "IconTheme.js",
    });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const iconTheme = context.iconTheme;
const themeDecision = context.themeDecision;
const restartCommand = context.restartCommand;
const relaunchCommand = context.relaunchCommand;

function check(ok, detail) {
    return { ok: ok, detail: detail };
}

function list(values) {
    return values.join(" ");
}

const cases = [
    {
        id: "theme_is_read_from_the_icons_section",
        name: "El tema se lee de la seccion [Icons]",
        run: () => iconTheme("[Icons]\nTheme=Tela-dark\n"),
        expect: (value) => check(value === "Tela-dark", String(value)),
    },
    {
        id: "value_is_trimmed",
        name: "El valor del tema va recortado",
        run: () => iconTheme("[Icons]\nTheme=  Tela-dark  \n"),
        expect: (value) => check(value === "Tela-dark", String(value)),
    },
    {
        id: "missing_section_gives_empty",
        name: "Sin seccion [Icons] no hay tema",
        run: () => iconTheme("[KDE]\nLookAndFeelPackage=org.pikaos.breeze-theme\n"),
        expect: (value) => check(value === "", String(value)),
    },
    {
        id: "missing_key_gives_empty",
        name: "Sin clave Theme no hay tema",
        run: () => iconTheme("[Icons]\n"),
        expect: (value) => check(value === "", String(value)),
    },
    {
        id: "empty_text_gives_empty",
        name: "Un archivo vacio no da tema",
        run: () => iconTheme(""),
        expect: (value) => check(value === "", String(value)),
    },
    {
        id: "other_sections_are_ignored",
        name: "La clave Theme de otra seccion no se cuenta",
        run: () => iconTheme("[KDE]\nTheme=Otro\n"),
        expect: (value) => check(value === "", String(value)),
    },
    {
        id: "comments_are_ignored",
        name: "Los comentarios no estorban",
        run: () => iconTheme("# comentario\n[Icons]\n; otro comentario\nTheme=breeze\n"),
        expect: (value) => check(value === "breeze", String(value)),
    },
    {
        id: "theme_stops_at_the_next_section",
        name: "El tema se queda en su seccion",
        run: () => iconTheme("[Icons]\nTheme=Tela-dark\n[KDE]\nTheme=breeze\n"),
        expect: (value) => check(value === "Tela-dark", String(value)),
    },
    {
        id: "a_new_theme_asks_for_a_restart",
        name: "Un tema nuevo pide reiniciar",
        run: () => themeDecision("Tela-dark", "breeze", true),
        expect: (decision) =>
            check(
                decision.theme === "breeze" && decision.restart === true,
                JSON.stringify(decision),
            ),
    },
    {
        id: "the_same_theme_keeps_the_shell",
        name: "El mismo tema deja la shell como estaba",
        run: () => themeDecision("Tela-dark", "Tela-dark", true),
        expect: (decision) =>
            check(
                decision.theme === "Tela-dark" && decision.restart === false,
                JSON.stringify(decision),
            ),
    },
    {
        id: "empty_value_keeps_the_previous_theme",
        name: "Una lectura vacia deja el tema anterior",
        run: () => themeDecision("Tela-dark", "", true),
        expect: (decision) =>
            check(
                decision.theme === "Tela-dark" && decision.restart === false,
                JSON.stringify(decision),
            ),
    },
    {
        id: "first_observed_theme_is_only_a_baseline",
        name: "El primer tema visto solo fija la linea base",
        run: () => themeDecision("", "breeze", false),
        expect: (decision) =>
            check(
                decision.theme === "breeze" && decision.restart === false,
                JSON.stringify(decision),
            ),
    },
    {
        id: "a_theme_that_appears_later_asks_for_a_restart",
        name: "Un tema que aparece mas tarde pide reiniciar",
        run: () => themeDecision("", "breeze", true),
        expect: (decision) =>
            check(
                decision.theme === "breeze" && decision.restart === true,
                JSON.stringify(decision),
            ),
    },
    {
        id: "the_restart_command_uses_a_transient_unit",
        name: "El reinicio va por una unidad transitoria",
        run: () => restartCommand("app-caparazon@autostart.service"),
        expect: (argv) =>
            check(
                argv[0] === "sh" &&
                    argv[1] === "-c" &&
                    argv[2].indexOf(
                        "systemd-run --user --on-active=0.3",
                    ) !== -1 &&
                    argv[argv.length - 1] === "app-caparazon@autostart.service",
                list(argv),
            ),
    },
    {
        id: "the_restart_command_falls_back_to_systemctl",
        name: "El reinicio cae a systemctl si no hay systemd-run",
        run: () => restartCommand("app-caparazon@autostart.service"),
        expect: (argv) =>
            check(
                argv[2].indexOf("command -v systemd-run") !== -1 &&
                    argv[2].indexOf("systemctl --user restart") !== -1,
                argv[2],
            ),
    },
    {
        id: "the_relaunch_command_waits_for_the_pid",
        name: "El relanzamiento espera a que muera el proceso actual",
        run: () => relaunchCommand(4242, ["quickshell", "-p", "/home/u/shell"]),
        expect: (argv) =>
            check(
                argv[0] === "sh" &&
                    argv[1] === "-c" &&
                    argv[2].indexOf("kill -0 4242") !== -1 &&
                    argv[argv.length - 3] === "quickshell" &&
                    argv[argv.length - 2] === "-p" &&
                    argv[argv.length - 1] === "/home/u/shell",
                list(argv),
            ),
    },
    {
        id: "the_relaunch_command_kills_the_current_process",
        name: "El relanzamiento mata al proceso actual para que vuelva",
        run: () => relaunchCommand(4242, ["quickshell", "-p", "/home/u/shell"]),
        expect: (argv) =>
            check(
                argv[2].indexOf("kill -TERM 4242") !== -1,
                argv[2],
            ),
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

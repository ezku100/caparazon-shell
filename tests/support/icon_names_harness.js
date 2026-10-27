// Escenarios del contrato de nombres de icono.
//
// El resolvedor de iconos vive en modules/icons/IconNames.js, que QML carga
// como JavaScript. Aquí se ejecuta ese mismo archivo con node para comprobar
// qué nombres alternativos se prueban cuando el nombre exacto no existe.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "icons", "IconNames.js");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(fs.readFileSync(modulePath, "utf8"), context, {
        filename: "IconNames.js",
    });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const candidates = context.candidates;
const iconKind = context.iconKind;

function check(ok, detail) {
    return { ok: ok, detail: detail };
}

function list(names) {
    return names.join(", ");
}

const cases = [
    {
        id: "exact_name_comes_first",
        name: "El nombre exacto es el primer candidato",
        run: () => candidates("com.obsproject.Studio"),
        expect: (names) =>
            check(
                names.length > 0 && names[0] === "com.obsproject.Studio",
                list(names),
            ),
    },
    {
        id: "symbolic_suffix_is_offered_without_the_suffix",
        name: "Un nombre -symbolic también se prueba sin el sufijo",
        run: () => candidates("firefox-symbolic"),
        expect: (names) =>
            check(names.indexOf("firefox") !== -1, list(names)),
    },
    {
        id: "lowercase_variant_is_offered",
        name: "Se ofrece la variante en minúsculas",
        run: () => candidates("Studio"),
        expect: (names) => check(names.indexOf("studio") !== -1, list(names)),
    },
    {
        id: "reverse_dns_suffixes_are_offered",
        name: "De un appId con dominio invertido se ofrecen los sufijos",
        run: () => candidates("com.obsproject.Studio"),
        expect: (names) =>
            check(
                names.indexOf("obsproject.Studio") !== -1 &&
                    names.indexOf("Studio") !== -1 &&
                    names.indexOf("obsproject") !== -1,
                list(names),
            ),
    },
    {
        id: "duplicates_are_removed",
        name: "Los nombres repetidos no se repiten",
        run: () => candidates("equibop"),
        expect: (names) =>
            check(
                names.length === new Set(names).size &&
                    names[0] === "equibop" &&
                    names.length === 2,
                list(names),
            ),
    },
    {
        id: "empty_name_has_no_candidates",
        name: "Un nombre vacío no propone nada",
        run: () => candidates(""),
        expect: (names) => check(names.length === 0, list(names)),
    },
    {
        id: "absolute_path_has_no_candidates",
        name: "Una ruta absoluta no se propone como nombre de icono",
        run: () => candidates("/usr/share/icons/hicolor/48x48/apps/obs.png"),
        expect: (names) => check(names.length === 0, list(names)),
    },
    {
        id: "absolute_path_is_a_path",
        name: "Una ruta absoluta se clasifica como ruta",
        run: () => iconKind("/usr/share/icons/hicolor/48x48/apps/obs.png"),
        expect: (kind) => check(kind === "path", String(kind)),
    },
    {
        id: "file_url_is_a_url",
        name: "Una URL file: se clasifica como URL",
        run: () => iconKind("file:///home/ezku/AppImages/.icons/citron"),
        expect: (kind) => check(kind === "url", String(kind)),
    },
    {
        id: "theme_name_is_a_name",
        name: "Un nombre de tema se clasifica como nombre",
        run: () => iconKind("com.obsproject.Studio"),
        expect: (kind) => check(kind === "name", String(kind)),
    },
    {
        id: "blank_name_is_empty",
        name: "Un nombre en blanco se clasifica como vacio",
        run: () => iconKind("   "),
        expect: (kind) => check(kind === "empty", String(kind)),
    },
    {
        id: "plain_name_keeps_only_useful_variants",
        name: "Un nombre simple no genera ruido",
        run: () => candidates("kitty"),
        expect: (names) =>
            check(
                names.length === 2 &&
                    names[0] === "kitty" &&
                    names[1] === "kitty-symbolic",
                list(names),
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

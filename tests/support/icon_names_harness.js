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
const stem = context.stem;
const nameFromPath = context.nameFromPath;
const iconRank = context.iconRank;

function check(ok, detail) {
    return { ok: ok, detail: detail };
}

function list(names) {
    return names.join(", ");
}

const cases = [
    {
        id: "query_string_is_stripped_from_names",
        name: "La query ?fallback= no ensucia los candidatos",
        run: () => candidates("media-playback-start-symbolic?fallback=media-stop"),
        expect: (names) =>
            check(
                names.length > 0 &&
                    names[0] === "media-playback-start-symbolic" &&
                    names.every((n) => n.indexOf("?") === -1),
                list(names),
            ),
    },
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
        id: "stem_strips_icon_extension",
        name: "El nombre base quita la extension de icono",
        run: () => stem("citron.png"),
        expect: (value) => check(value === "citron", String(value)),
    },
    {
        id: "stem_keeps_non_icon_extension",
        name: "Una extension que no es de icono se conserva",
        run: () => stem("archive.tar.gz"),
        expect: (value) => check(value === "archive.tar.gz", String(value)),
    },
    {
        id: "stem_keeps_extensionless_name",
        name: "Un nombre sin extension se queda igual",
        run: () => stem("app"),
        expect: (value) => check(value === "app", String(value)),
    },
    {
        id: "path_name_takes_last_segment",
        name: "De una ruta se toma el ultimo segmento",
        run: () => nameFromPath("/home/u/AppImages/.icons/citron"),
        expect: (value) => check(value === "citron", String(value)),
    },
    {
        id: "path_name_strips_extension",
        name: "De una ruta con extension se toma el nombre sin extension",
        run: () => nameFromPath("/opt/obs.png"),
        expect: (value) => check(value === "obs", String(value)),
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
        id: "image_url_is_a_url",
        name: "Una URL image:// ya resuelta se clasifica como URL",
        run: () => iconKind("image://icon/com.obsproject.Studio"),
        expect: (kind) => check(kind === "url", String(kind)),
    },
    {
        id: "qrc_url_is_a_url",
        name: "Una URL qrc: se clasifica como URL",
        run: () => iconKind("qrc:/icons/x.png"),
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
    {
        id: "scalable_variant_wins_over_the_small_ones",
        name: "La variante escalable vale mas que las pequeñas",
        run: () => [
            iconRank("/usr/share/icons/Papirus-Dark/16x16/places/folder.png"),
            iconRank(
                "/usr/share/icons/Papirus-Dark/scalable/places/folder.svg",
            ),
        ],
        expect: (ranks) =>
            check(ranks[1] > ranks[0], list(ranks)),
    },
    {
        id: "medium_variant_wins_over_the_tiny_one",
        name: "La variante de 48 gana a la de 16",
        run: () => [
            iconRank("/usr/share/icons/Papirus-Dark/16x16/places/folder.png"),
            iconRank("/usr/share/icons/Papirus-Dark/48x48/places/folder.png"),
        ],
        expect: (ranks) => check(ranks[1] > ranks[0], list(ranks)),
    },
    {
        id: "vector_wins_over_the_bitmap_of_the_same_size",
        name: "El vector gana al mapa de bits del mismo tamaño",
        run: () => [
            iconRank("/usr/share/icons/Papirus-Dark/48x48/places/folder.png"),
            iconRank("/usr/share/icons/Papirus-Dark/48x48/places/folder.svg"),
        ],
        expect: (ranks) => check(ranks[1] > ranks[0], list(ranks)),
    },
    {
        id: "file_without_a_size_directory_has_a_middle_rank",
        name: "Un icono sin carpeta de tamaño tiene un valor intermedio",
        run: () => iconRank("/usr/share/icons/Adwaita/folder.svg"),
        expect: (rank) =>
            check(
                rank > iconRank("/usr/share/icons/Adwaita/16x16/folder.png") &&
                    rank <
                        iconRank("/usr/share/icons/Adwaita/scalable/folder.svg"),
                String(rank),
            ),
    },
    {
        id: "active_theme_wins_over_inherited_even_at_a_smaller_size",
        name: "El tema activo gana al heredado aunque sea mas pequeño",
        run: () => [
            iconRank("/usr/share/icons/Activo/16x16/apps/foo.png", [
                "Activo",
                "Heredado",
                "hicolor",
            ]),
            iconRank("/usr/share/icons/hicolor/scalable/apps/foo.svg", [
                "Activo",
                "Heredado",
                "hicolor",
            ]),
        ],
        expect: (ranks) => check(ranks[0] > ranks[1], list(ranks)),
    },
    {
        id: "inherited_theme_wins_over_hicolor",
        name: "Un tema heredado gana a hicolor",
        run: () => [
            iconRank("/home/u/.icons/Heredado/48x48/apps/foo.png", [
                "Activo",
                "Heredado",
                "hicolor",
            ]),
            iconRank("/usr/share/icons/hicolor/scalable/apps/foo.svg", [
                "Activo",
                "Heredado",
                "hicolor",
            ]),
        ],
        expect: (ranks) => check(ranks[0] > ranks[1], list(ranks)),
    },
    {
        id: "size_ranking_is_kept_inside_the_same_theme",
        name: "Dentro de un tema sigue ganando la mejor variante",
        run: () => [
            iconRank("/usr/share/icons/Activo/16x16/apps/foo.png", [
                "Activo",
                "hicolor",
            ]),
            iconRank("/usr/share/icons/Activo/scalable/apps/foo.svg", [
                "Activo",
                "hicolor",
            ]),
        ],
        expect: (ranks) => check(ranks[1] > ranks[0], list(ranks)),
    },
    {
        id: "icons_outside_the_search_order_have_no_theme_bonus",
        name: "Un icono fuera de los temas no recibe bonus de tema",
        run: () => [
            iconRank("/home/u/.local/share/applications/foo.png", [
                "Activo",
                "hicolor",
            ]),
            iconRank("/home/u/.local/share/applications/foo.png"),
        ],
        expect: (ranks) => check(ranks[0] === ranks[1], list(ranks)),
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

// Escenarios de la lógica del calendario del menú secundario.
//
// La lógica vive en modules/secondmenu/CalendarMath.js, que QML carga como
// JavaScript. Aquí se ejecuta ese mismo archivo con node (sin la directiva
// .pragma library, que sólo entiende QML) para comprobar la rejilla del mes.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "secondmenu", "CalendarMath.js");

const source = fs
    .readFileSync(modulePath, "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(source, context, { filename: "CalendarMath.js" });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const {
    monthDays,
    firstWeekday,
    monthName,
    monthLabel,
    monthGrid,
    dayKey,
    isSameDay,
    colorsForDay,
} = context;

function gridShape() {
    const grid = monthGrid(2026, 10);
    return JSON.stringify({
        weeks: grid.length,
        rows: grid.map((week) => week.length),
    });
}

const cases = [
    {
        id: "bisiesto",
        detail: "febrero de 2024 tiene 29 días",
        run: () => monthDays(2024, 2),
        expected: 29,
    },
    {
        id: "febrero-comun",
        detail: "febrero de 2023 tiene 28 días",
        run: () => monthDays(2023, 2),
        expected: 28,
    },
    {
        id: "mes-31",
        detail: "octubre tiene 31 días",
        run: () => monthDays(2026, 10),
        expected: 31,
    },
    {
        id: "mes-30",
        detail: "abril tiene 30 días",
        run: () => monthDays(2026, 4),
        expected: 30,
    },
    {
        id: "primer-dia-octubre-2026",
        detail: "el 1 de octubre de 2026 es jueves (3 con lunes = 0)",
        run: () => firstWeekday(2026, 10),
        expected: 3,
    },
    {
        id: "primer-dia-febrero-2024",
        detail: "el 1 de febrero de 2024 es jueves",
        run: () => firstWeekday(2024, 2),
        expected: 3,
    },
    {
        id: "primera-celda",
        detail: "la rejilla de octubre de 2026 empieza el 28 de septiembre",
        run: () => monthGrid(2026, 10)[0][0].day,
        expected: 28,
    },
    {
        id: "celda-dia-uno",
        detail: "el 1 de octubre cae en la cuarta columna y es del mes",
        run: () => JSON.stringify(monthGrid(2026, 10)[0][3]),
        expected: '{"day":1,"month":10,"year":2026,"current":true}',
    },
    {
        id: "ultima-celda",
        detail: "la rejilla termina el 8 de noviembre",
        run: () => {
            const last = monthGrid(2026, 10)[5][6];
            return JSON.stringify({ day: last.day, month: last.month });
        },
        expected: '{"day":8,"month":11}',
    },
    {
        id: "seis-semanas",
        detail: "la rejilla siempre tiene 6 semanas de 7 días",
        run: gridShape,
        expected: '{"weeks":6,"rows":[7,7,7,7,7,7]}',
    },
    {
        id: "mes-empieza-domingo",
        detail: "febrero de 2026 empieza en domingo y arranca el 26 de enero",
        run: () => monthGrid(2026, 2)[0][0].day,
        expected: 26,
    },
    {
        id: "diciembre-cruza-de-ano",
        detail: "la rejilla de diciembre de 2026 termina en enero de 2027",
        run: () => {
            const last = monthGrid(2026, 12)[5][6];
            return JSON.stringify({ month: last.month, year: last.year });
        },
        expected: '{"month":1,"year":2027}',
    },
    {
        id: "nombre-mes",
        detail: "el mes 10 se llama octubre",
        run: () => monthName(10),
        expected: "octubre",
    },
    {
        id: "etiqueta-mes",
        detail: "la etiqueta une mes y año",
        run: () => monthLabel(2026, 10),
        expected: "octubre 2026",
    },
    {
        id: "clave-dia",
        detail: "dayKey rellena mes y día con dos dígitos",
        run: () => dayKey(2026, 3, 7),
        expected: "2026-03-07",
    },
    {
        id: "clave-dia-dos-digitos",
        detail: "dayKey no toca los meses y días de dos dígitos",
        run: () => dayKey(2026, 11, 23),
        expected: "2026-11-23",
    },
    {
        id: "mismo-dia-si",
        detail: "isSameDay compara año, mes y día",
        run: () => isSameDay(
            { year: 2026, month: 11, day: 3 },
            { year: 2026, month: 11, day: 3 },
        ),
        expected: true,
    },
    {
        id: "mismo-dia-no",
        detail: "isSameDay distingue días distintos",
        run: () => isSameDay(
            { year: 2026, month: 11, day: 3 },
            { year: 2026, month: 11, day: 4 },
        ),
        expected: false,
    },
    {
        id: "colores-orden-config",
        detail: "colorsForDay devuelve colores distintos en el orden de la configuración",
        run: () => {
            const byDay = {
                "2026-11-03": [
                    { calendar_id: "casa", color: "#34A853" },
                    { calendar_id: "trabajo", color: "#4285F4" },
                    { calendar_id: "trabajo", color: "#4285F4" },
                ],
            };
            return JSON.stringify(
                colorsForDay(byDay, 2026, 11, 3, ["trabajo", "casa"]),
            );
        },
        expected: '["#4285F4","#34A853"]',
    },
    {
        id: "colores-dia-vacio",
        detail: "un día sin eventos no tiene colores",
        run: () => JSON.stringify(colorsForDay({}, 2026, 11, 3, [])),
        expected: "[]",
    },
    {
        id: "colores-sin-orden",
        detail: "sin orden configurado, los colores salen en el orden de los eventos",
        run: () => {
            const byDay = {
                "2026-11-03": [
                    { calendar_id: "casa", color: "#34A853" },
                    { calendar_id: "trabajo", color: "#4285F4" },
                ],
            };
            return JSON.stringify(colorsForDay(byDay, 2026, 11, 3, []));
        },
        expected: '["#34A853","#4285F4"]',
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

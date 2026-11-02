.pragma library

// Lógica del calendario mensual, sin dependencias de QML. La semana empieza
// en lunes (0 = lunes ... 6 = domingo), como en México y en el resto de
// freedesktop.

var WEEKDAY_LABELS = ["L", "M", "X", "J", "V", "S", "D"];

var MONTH_NAMES = [
    "enero", "febrero", "marzo", "abril", "mayo", "junio",
    "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"
];

// Días que tiene el mes (month 1..12). El día 0 del mes siguiente es el
// último del actual.
function monthDays(year, month) {
    return new Date(year, month, 0).getDate();
}

// Día de la semana del día 1: 0 = lunes ... 6 = domingo.
function firstWeekday(year, month) {
    var wd = new Date(year, month - 1, 1).getDay(); // 0 = domingo
    return (wd + 6) % 7;
}

function monthName(month) {
    var index = ((month - 1) % 12 + 12) % 12;
    return MONTH_NAMES[index];
}

function monthLabel(year, month) {
    return monthName(month) + " " + year;
}

// Rejilla de 6 semanas (42 celdas). Cada celda: { day, month, year, current }
// con current = false para los días de los meses vecinos.
function monthGrid(year, month) {
    var total = monthDays(year, month);
    var start = firstWeekday(year, month);

    var prevMonth = month === 1 ? 12 : month - 1;
    var prevYear = month === 1 ? year - 1 : year;
    var prevTotal = monthDays(prevYear, prevMonth);

    var nextMonth = month === 12 ? 1 : month + 1;
    var nextYear = month === 12 ? year + 1 : year;

    var cells = [];
    for (var i = start - 1; i >= 0; --i)
        cells.push({ day: prevTotal - i, month: prevMonth, year: prevYear, current: false });

    for (var d = 1; d <= total; ++d)
        cells.push({ day: d, month: month, year: year, current: true });

    var next = 1;
    while (cells.length < 42) {
        cells.push({ day: next, month: nextMonth, year: nextYear, current: false });
        next += 1;
    }

    var weeks = [];
    for (var w = 0; w < 6; ++w)
        weeks.push(cells.slice(w * 7, w * 7 + 7));
    return weeks;
}

function isToday(year, month, day) {
    var now = new Date();
    return now.getFullYear() === year
        && (now.getMonth() + 1) === month
        && now.getDate() === day;
}

// Clave de día en formato ISO: "AAAA-MM-DD". Es la misma clave que usa el
// script de calendarios, así que ambos lados hablan el mismo idioma.
function dayKey(year, month, day) {
    var mm = month < 10 ? "0" + month : "" + month;
    var dd = day < 10 ? "0" + day : "" + day;
    return year + "-" + mm + "-" + dd;
}

// Compara dos días con la forma { year, month, day }.
function isSameDay(a, b) {
    if (!a || !b)
        return false;
    return a.year === b.year && a.month === b.month && a.day === b.day;
}

// Colores de los calendarios con eventos ese día, sin repetir y en el orden
// de la configuración; los que no estén en él se cuelgan al final.
function colorsForDay(byDay, year, month, day, order) {
    var events = (byDay && byDay[dayKey(year, month, day)]) || [];
    if (!events || events.length === 0)
        return [];

    var colors = [];
    var seen = Object.create(null);
    var ids = order && order.length ? order.slice() : [];

    for (var i = 0; i < ids.length; ++i) {
        var id = ids[i];
        if (seen[id])
            continue;
        for (var j = 0; j < events.length; ++j) {
            if (events[j].calendar_id === id) {
                seen[id] = true;
                if (events[j].color && colors.indexOf(events[j].color) === -1)
                    colors.push(events[j].color);
                break;
            }
        }
    }

    for (var k = 0; k < events.length; ++k) {
        var event = events[k];
        if (seen[event.calendar_id])
            continue;
        seen[event.calendar_id] = true;
        if (event.color && colors.indexOf(event.color) === -1)
            colors.push(event.color);
    }
    return colors;
}

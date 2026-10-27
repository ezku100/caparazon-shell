// Tema de iconos de KDE: lectura, decisión y comando de reinicio.
//
// El tema de iconos se lee una sola vez por proceso: Qt lo carga al
// arrancar y no vuelve a mirarlo. Por eso, cuando KDE cambia de tema, la
// shell tiene que reiniciarse para que los iconos cambien.
//
// Aquí vive toda la decisión, en JavaScript plano, para poder probarla con
// node sin levantar la shell. El QML sólo vigila el archivo y llama aquí.
//
// El estado es ninguno: cada función devuelve su resultado.

var ICONS_SECTION = "icons";
var THEME_KEY = "theme";

// Valor de la clave Theme de la sección [Icons]; "" si no está.
//
// KConfig reescribe el archivo entero cuando cambia algo, así que una
// lectura puede encontrar la sección a medio escribir: en ese caso no hay
// tema y la shell se queda con el que ya tenía.
function iconTheme(text) {
    var raw = typeof text === "string" ? text : "";
    var lines = raw.split("\n");
    var section = "";
    var result = "";

    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim();
        if (line.length === 0 || line.charAt(0) === "#" || line.charAt(0) === ";")
            continue;

        // Una sección nueva cierra la anterior.
        if (line.charAt(0) === "[") {
            var close = line.indexOf("]");
            section = line
                .slice(1, close === -1 ? line.length : close)
                .trim()
                .toLowerCase();
            continue;
        }

        if (section !== ICONS_SECTION)
            continue;

        var equals = line.indexOf("=");
        if (equals === -1)
            continue;
        if (line.slice(0, equals).trim().toLowerCase() !== THEME_KEY)
            continue;

        result = line.slice(equals + 1).trim();
        break;
    }

    if (result.length >= 2 && result.charAt(0) === "\"" && result.charAt(result.length - 1) === "\"")
        result = result.slice(1, result.length - 1);
    return result;
}

// Qué tema queda como referencia y si hay que reiniciar la shell.
//
// El primer valor que se ve tras arrancar es la línea base: fijarlo no
// reinicia nada, porque el proceso ya ha arrancado con ese tema. A partir de
// ahí, un valor distinto y no vacío sí pide reinicio.
function themeDecision(previous, current, baselineKnown) {
    var before = typeof previous === "string" ? previous : "";
    var now = typeof current === "string" ? current : "";

    if (now.length === 0)
        return { theme: before, restart: false };
    if (!baselineKnown)
        return { theme: now, restart: false };
    if (now !== before)
        return { theme: now, restart: true };
    return { theme: before, restart: false };
}

// Comando que reinicia la unidad de la shell.
//
// La unidad transitoria vive fuera del cgroup de la shell: así el reinicio
// no se mata a sí mismo a media faena. Si no hay systemd-run, se cae a
// systemctl, que encola el reinicio en el gestor aunque el cliente muera
// con la shell.
//
// La unidad viaja como argumento y nunca pegada al script, para que no haya
// problemas de comillas.
function restartCommand(unit) {
    var target = typeof unit === "string" ? unit : "";
    var script =
        "command -v systemd-run >/dev/null 2>&1 && "
        + "systemd-run --user --on-active=0.3 --unit=caparazon-icon-theme-reload "
        + "systemctl --user restart \"$1\" || systemctl --user restart \"$1\"";
    return ["sh", "-c", script, "caparazon-reload", target];
}

// Comando que relanza la shell cuando el proceso actual haya muerto.
//
// Se usa cuando la shell no corre bajo systemd: se espera a que el PID
// actual desaparezca y se vuelve a ejecutar el mismo argv.
function relaunchCommand(pid, argv) {
    var args = [];
    if (Array.isArray(argv)) {
        for (var i = 0; i < argv.length; ++i) {
            var value = String(argv[i]);
            if (value.length > 0)
                args.push(value);
        }
    }
    var script =
        "while kill -0 " + String(pid) + " 2>/dev/null; do sleep 0.2; done; exec \"$@\"";
    return ["sh", "-c", script, "caparazon-relaunch"].concat(args);
}

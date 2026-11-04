// Acción de ventana para el dock: enfoca, minimiza o restaura la ventana de
// una app.
//
// Quickshell sustituye los marcadores antes de cargarlo en KWin:
//   __TARGET__  appIds candidatos de la app pulsada, separados por "|"
//   __ACTIVE__  appId que la shell cree que está enfocada (puede ir vacío)
//
// La decisión se toma aquí, y no en el QML, porque KWin es el único sitio donde
// se sabe si una ventana está minimizada: KWin 6.7.4 no implementa
// ext-foreign-toplevel-management y Quickshell no ve ese estado.
//
// Reglas:
//   - hay una ventana minimizada  -> se restaura y se enfoca
//   - la app está enfocada        -> se minimiza
//   - la app no está enfocada     -> se enfoca (comportamiento de siempre)

function appIdFor(window) {
    return window.desktopFileName || window.resourceClass || window.resourceName || "";
}

function normalizeId(id) {
    return String(id || "").toLowerCase().replace(/\.desktop$/, "");
}

function candidatesOf(target) {
    const ids = [];
    const parts = String(target || "").split("|");
    for (let i = 0; i < parts.length; ++i) {
        const id = normalizeId(parts[i]);
        if (id && ids.indexOf(id) === -1)
            ids.push(id);
    }
    return ids;
}

function windowsOf(targets) {
    const wanted = candidatesOf(targets);
    return workspace.windowList().filter(function(window) {
        return window && !window.deleted && window.normalWindow
            && !window.skipTaskbar
            && wanted.indexOf(normalizeId(appIdFor(window))) !== -1;
    });
}

function isFromApp(window, targets) {
    if (!window)
        return false;
    return candidatesOf(targets).indexOf(normalizeId(appIdFor(window))) !== -1;
}

function restore(window) {
    window.minimized = false;
    workspace.activeWindow = window;
}

function minimize(window) {
    window.minimized = true;
}

function focus(window) {
    workspace.activeWindow = window;
}

function applyAction(targets, activeHint) {
    const windows = windowsOf(targets);
    if (windows.length === 0)
        return "none";

    // Una ventana minimizada manda: el usuario la escondió y la quiere de
    // vuelta. Se restaura la última minimizada y se enfoca.
    const minimized = windows.filter(function(window) {
        return window.minimized === true;
    });
    if (minimized.length > 0) {
        restore(minimized[minimized.length - 1]);
        return "restore";
    }

    const activeWindow = workspace.activeWindow;
    const activeIsTarget = isFromApp(activeWindow, targets);
    // La pista de la shell cubre el caso en que el clic robó el foco: sin ella
    // no se podría distinguir "enfocar" de "minimizar".
    const hintIsTarget = !!activeHint
        && candidatesOf(targets).indexOf(normalizeId(activeHint)) !== -1;

    if (activeIsTarget || hintIsTarget) {
        minimize(activeIsTarget ? activeWindow : windows[windows.length - 1]);
        return "minimize";
    }

    focus(windows[windows.length - 1]);
    return "focus";
}

const target = "__TARGET__";
const activeHint = "__ACTIVE__";

const action = applyAction(target, activeHint);
console.info("CAPARAZON_WINDOW_ACTION:" + JSON.stringify({ target: target, action: action }));

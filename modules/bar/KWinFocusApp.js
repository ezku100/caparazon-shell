// Activa la ventana de la app solicitada. Quickshell genera una copia
// temporal de este archivo sustituyendo __TARGET__ por el appId elegido.
function appIdFor(window) {
    return window.desktopFileName || window.resourceClass || window.resourceName || "";
}

function normalizeId(id) {
    return String(id || "").toLowerCase().replace(/\.desktop$/, "");
}

const target = "__TARGET__";
const wanted = normalizeId(target);
const windows = workspace.windowList().filter(function(window) {
    return window && !window.deleted && window.normalWindow &&
        !window.skipTaskbar && normalizeId(appIdFor(window)) === wanted;
});

if (windows.length > 0)
    workspace.activeWindow = windows[windows.length - 1];

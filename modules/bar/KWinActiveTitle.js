// KWin no expone la ventana activa por DBus. Este script observa KWin y
// escribe appId + título en el journal con un prefijo parseable por Quickshell.
// Se carga dinámicamente desde ActiveWindowService.qml.
//
// Además publica la lista de ventanas normales para que el dock pueda contar
// instancias por aplicación sin depender de ext-foreign-toplevel (KWin no lo
// expone en esta versión).

let lastKey = null;
let lastWindowsKey = null;
const watched = new Set();

function appIdFor(window) {
    return window.desktopFileName || window.resourceClass || window.resourceName || "";
}

function activeInfo() {
    const window = workspace.activeWindow;
    if (!window)
        return { appId: "", title: "" };

    return {
        appId: appIdFor(window),
        title: window.caption || ""
    };
}

function report() {
    const info = activeInfo();
    const key = info.appId + "\n" + info.title;

    if (key === lastKey)
        return;

    lastKey = key;
    console.info("CAPARAZON_ACTIVE:" + JSON.stringify(info));
}

function windowAppIds() {
    const ids = [];

    workspace.windowList().forEach(function(window) {
        if (!window || window.deleted || !window.normalWindow || window.skipTaskbar)
            return;

        const appId = appIdFor(window);
        if (appId)
            ids.push(appId);
    });

    return ids;
}

function reportWindows() {
    const ids = windowAppIds();
    const key = JSON.stringify(ids);

    if (key === lastWindowsKey)
        return;

    lastWindowsKey = key;
    console.info("CAPARAZON_WINDOWS:" + key);
}

function watch(window) {
    if (!window || watched.has(window))
        return;

    watched.add(window);
    window.captionChanged.connect(report);
    window.closed.connect(function() {
        watched.delete(window);
        reportWindows();
    });
}

workspace.windowList().forEach(watch);
workspace.windowAdded.connect(function(window) {
    watch(window);
    reportWindows();
});
workspace.windowActivated.connect(report);

report();
reportWindows();

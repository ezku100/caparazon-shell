// Puente escritorios -> org.ezku.Desktops (widgets pacman y faro de Noctalia).
// Empuja {current, desktops:[{pos,id,name}], occupied:[ids],
// active:{caption, class, uuid}} en cada cambio.
var pendingDesktopByScreen = {};

// El signal currentDesktopChanged ya trae el escritorio nuevo. KWin a veces
// actualiza currentDesktopForScreen un instante después; guardamos ese valor
// como override temporal para que la barra no se quede en el anterior.
var settleTimer = null;
try {
    settleTimer = new QTimer();
    settleTimer.interval = 70;
    settleTimer.singleShot = true;
    settleTimer.timeout.connect(function () { push(); });
} catch (e) {}

function schedulePush() {
    push();
    try { if (settleTimer) { settleTimer.start(); } } catch (e) {}
}

function onDesktopChanged(previous, current, screen) {
    try {
        var screenName = screen ? String(screen.name || "") : "";
        var desktopId = deskId(current);
        if (screenName && desktopId) {
            pendingDesktopByScreen[screenName] = desktopId;
        }
    } catch (e) {}
    schedulePush();
}

function deskId(d) {
    try { return d ? String(d.id) : ""; } catch (e) { return ""; }
}

function push() {
    try {
        var list = [];
        var ds = workspace.desktops || [];
        for (var i = 0; i < ds.length; i++) {
            list.push({ pos: i, id: deskId(ds[i]), name: String(ds[i].name || ("Escritorio " + (i + 1))) });
        }
        var occ = [];
        var occByOutput = {};
        var screens = [];
        try {
            screens = workspace.screens || [];
            for (var s = 0; s < screens.length; s++) {
                var screenName0 = String(screens[s].name || "");
                if (screenName0) { occByOutput[screenName0] = []; }
            }
        } catch (e0) {}
        var clients = windowList();
        for (var j = 0; j < clients.length; j++) {
            var c = clients[j];
            try {
                if (!c || c.skipTaskbar || c.skipPager || c.desktopWindow || c.dock) { continue; }
            } catch (e) { continue; }
            var ids = deskIds(c);
            try {
                if (c.onAllDesktops) {
                    ids = [];
                    for (var d = 0; d < ds.length; d++) { ids.push(deskId(ds[d])); }
                }
            } catch (eAll) {}
            var outName = "";
            try { outName = c.output ? String(c.output.name || "") : ""; } catch (eOut) {}
            if (outName && !occByOutput[outName]) { occByOutput[outName] = []; }
            for (var m = 0; m < ids.length; m++) {
                if (occ.indexOf(ids[m]) === -1) { occ.push(ids[m]); }
                if (outName && occByOutput[outName].indexOf(ids[m]) === -1) {
                    occByOutput[outName].push(ids[m]);
                }
            }
        }
        var cur = "";
        try { cur = deskId(workspace.currentDesktop); } catch (e) {}
        var perOutput = {};
        try {
            var screens = workspace.screens || [];
            for (var s = 0; s < screens.length; s++) {
                var screen = screens[s];
                var screenName = String(screen.name || "");
                if (screenName) {
                    perOutput[screenName] = deskId(workspace.currentDesktopForScreen(screen));
                }
            }
        } catch (e3) {}
        try {
            for (var pendingScreen in pendingDesktopByScreen) {
                if (Object.prototype.hasOwnProperty.call(pendingDesktopByScreen, pendingScreen)) {
                    var pendingId = pendingDesktopByScreen[pendingScreen];
                    if (perOutput[pendingScreen] === pendingId) {
                        // KWin ya confirmó el cambio; dejamos de forzarlo.
                        delete pendingDesktopByScreen[pendingScreen];
                    } else {
                        // KWin todavía reporta el anterior: mantenemos el nuevo.
                        perOutput[pendingScreen] = pendingId;
                    }
                }
            }
        } catch (ePending) {}
        var focusedScreen = "";
        try {
            var awScreen = workspace.activeWindow && workspace.activeWindow.output;
            if (awScreen) { focusedScreen = String(awScreen.name || ""); }
        } catch (e4) {}
        if (!focusedScreen) {
            try { focusedScreen = String(workspace.activeScreen.name || ""); } catch (e5) {}
        }
        var act = { caption: "", class: "", uuid: "" };
        try {
            var aw = workspace.activeWindow;
            if (aw) {
                act.caption = String(aw.caption || "");
                act.class = String(aw.resourceClass || aw.resourceName || "");
                try { act.uuid = String(aw.internalId || ""); } catch (e2) {}
            }
        } catch (e) {}
        callDBus("org.ezku.Desktops", "/Desktops", "org.ezku.Desktops",
            "PushState", JSON.stringify({ current: cur, desktops: list, occupied: occ, active: act,
                                          windows: windowAppIds(),
                                          perOutput: perOutput, focusedScreen: focusedScreen, occupiedPerOutput: occByOutput }));
    } catch (e) { /* demonio aún no corre; reintentará en el próximo cambio */ }
}

function windowList() {
    try {
        if (workspace.stackingOrder && workspace.stackingOrder.length) { return workspace.stackingOrder; }
    } catch (e) {}
    try {
        if (workspace.clientList) { return workspace.clientList(); }
    } catch (e) {}
    return [];
}

function deskIds(c) {
    var out = [];
    try {
        var arr = c.desktops;
        if (arr && arr.length) {
            for (var i = 0; i < arr.length; i++) {
                var id = deskId(arr[i]);
                if (id && out.indexOf(id) === -1) { out.push(id); }
            }
            if (out.length) { return out; }
        }
    } catch (e) {}
    try {
        var single = deskId(c.desktop);
        if (single) { out.push(single); }
    } catch (e) {}
    return out;
}

// appId de cada ventana normal (no dock, no pager, no saltar barra de tareas).
// Se reusa para escritorio ocupado y para la lista de ventanas abiertas del dock.
function windowAppIds() {
    var ids = [];
    var list = windowList();
    for (var j = 0; j < list.length; j++) {
        var c = list[j];
        try {
            if (!c || c.deleted || !c.normalWindow || c.skipTaskbar) { continue; }
        } catch (e) { continue; }
        var appId = String(c.desktopFileName || c.resourceClass || c.resourceName || "");
        if (appId) { ids.push(appId); }
    }
    return ids;
}

function watchClient(c) {
    try {
        if (c.desktopChanged && c.desktopChanged.connect) { c.desktopChanged.connect(push); }
    } catch (e) {}
    try {
        if (c.skipTaskbarChanged && c.skipTaskbarChanged.connect) { c.skipTaskbarChanged.connect(push); }
    } catch (e) {}
    try {
        if (c.outputChanged && c.outputChanged.connect) { c.outputChanged.connect(push); }
    } catch (e) {}
    try {
        if (c.onAllDesktopsChanged && c.onAllDesktopsChanged.connect) { c.onAllDesktopsChanged.connect(push); }
    } catch (e) {}
    try {
        if (c.captionChanged && c.captionChanged.connect) {
            c.captionChanged.connect(function () {
                try { if (workspace.activeWindow === c) { push(); } } catch (e) {}
            });
        }
    } catch (e) {}
}

function onConnect(obj, name, fn) {
    try {
        if (obj && obj[name] && obj[name].connect) { obj[name].connect(fn); return true; }
    } catch (e) {}
    return false;
}

try {
    var initial = windowList();
    for (var k = 0; k < initial.length; k++) { watchClient(initial[k]); }
    onConnect(workspace, "clientAdded", function (c) { watchClient(c); push(); });
    onConnect(workspace, "windowAdded", function (c) { watchClient(c); push(); });
    onConnect(workspace, "clientRemoved", push);
    onConnect(workspace, "windowRemoved", push);
    onConnect(workspace, "currentDesktopChanged", onDesktopChanged);
    onConnect(workspace, "desktopsChanged", push);
    onConnect(workspace, "windowActivated", push);
    onConnect(workspace, "clientActivated", push);
    onConnect(workspace, "activeWindowChanged", push);
    onConnect(workspace, "activeOutputChanged", push);
} catch (e) {}

push();

# Dock inteligente (esquiva ventanas) — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el dock se oculte solo cuando una ventana se maximiza (liberando su franja reservada), reaparezca usable al acercar el puntero al borde inferior, y vuelva a su sitio cuando la ventana se cierre o deje de estar maximizada.

**Architecture:** El script de KWin del puente `ezkudesktops` detecta qué salidas tienen una ventana maximizada o a pantalla completa (comparando `frameGeometry` contra `clientArea(MaximizeArea, …)`) y lo publica por D-Bus; el demonio lo persiste en `~/.cache/ezku-desktops.json`; `ActiveWindowService.qml` lo lee con el `FileView` que ya vigila ese archivo. El dock traduce ese dato a tres estados (`normal`, `hidden`, `revealed`) con una pequeña librería JS pura (`DockSmartHide.js`), y de ahí salen la `exclusiveZone`, la `mask` (input region), el desplazamiento y la opacidad.

**Tech Stack:** Quickshell 0.3.2 (QML/Qt 6.10), KWin 6.7.4 (scripts en JavaScript), Python 3.11+ (demonio D-Bus con PyGObject), pytest + node (harnesses `vm`) para tests, ruff + basedpyright.

**Spec:** `docs/superpowers/specs/2026-11-02-dock-inteligente-design.md`

## Global Constraints

- KWin 6.7.4 / Quickshell 0.3.2 / Qt 6.10. Wayland. No se toca la configuración de KDE.
- `Theme.dockHeight = 52`, `Theme.shadowPad = 12` → la superficie del dock mide 64 px.
- Estados: `normal` | `hidden` | `revealed`. `hidden` y `revealed` sólo existen con `covered = true`.
- `exclusiveZone`: `dockHeight + bottomGap` en `normal`; **0** en `hidden` y en `revealed` (la ventana maximizada no se redimensiona al revelar).
- Franja sensible: **6 px** de alto, ancho = `dockWidth`, pegada al borde inferior. Tolerancia de comparación de geometría: **2 px**. Gracia antes de volver a esconder: **250 ms**. Duración del deslizamiento: **`Theme.dur` (220 ms)**, `Easing.OutCubic`.
- Todo es por salida: se compara el nombre de salida de KWin (`DP-1`) con `screen.name` de Quickshell.
- Los QML y JS llevan comentarios en español; los nombres de test en inglés con docstring en español (estilo del repo).
- Todo `Theme.<token>` usado en un QML debe estar declarado en `theme/Theme.qml` (`tests/test_theme_tokens.py` lo exige).
- Barra de calidad: `uv run pytest -q` en verde (351 tests antes de empezar), `uv run ruff check` limpio, y **no añadir** errores de basedpyright (hay 44 preexistentes).
- Commits: sólo si el humano lo ha pedido explícitamente; si no, dejar los cambios en el árbol.
- El script de KWin instalado vive en `~/.local/share/kwin/scripts/ezkudesktops/contents/code/main.js` y lo copia `install.sh` desde el repo.

## Review Focus

- Ventana maximizada en **otra** salida: el dock de esta pantalla no debe esconderse. Lo fija `test_dock_covering` (agrupación por `output.name`) y `test_dock_smart_hide` (`isCovered` por nombre).
- **Cerrar** la ventana (no sólo quitar el maximizado): el dock debe volver. Lo fija el escenario de ventana eliminada del harness del puente (`covering` vacío) más el push en `windowRemoved`/`clientRemoved`.
- Puntero **sobre** el dock con la ventana maximizada: debe seguir visible y ser usable. Lo fija `stateFor(true, true) === "revealed"` y que la máscara de `revealed` sea la del dock (6 px ⊂ 52 px).
- La shell arranca con una ventana **ya maximizada**: el dock debe empezar oculto. Lo fija `isCovered()` sobre el mapa del caché y la carga inicial del `FileView`.
- Un **diálogo** o una ventana normal no maximizada no deben esconder el dock. Lo fijan los escenarios "ventana normal" y `skipTaskbar` del harness del puente.
- La franja sensible no debe robar clics **fuera del ancho del dock**: `maskRect` usa `dockWidth`, no el ancho de la pantalla.

---

### Task 1: Sonda de la API de KWin (spike desechable)

**Files:**
- Create (temporal, fuera del repo): `/tmp/opencode/kwin-cover-probe.js`
- Modify: ninguno

**Interfaces:**
- Consumes: nada.
- Produces: la variante exacta de `clientArea` que funciona en este KWin, y si `maximizedChanged`/`fullScreenChanged` existen. Se documenta en el propio chat/tarea; el fichero de la sonda no se commitea.

- [ ] **Step 1: Escribir la sonda**

```js
// /tmp/opencode/kwin-cover-probe.js
function log(tag, value) { console.info("CAPARAZON_PROBE:" + tag + "=" + value); }
log("enum-workspace", typeof workspace.MaximizeArea);
log("enum-window", typeof Window);
var list = workspace.windowList ? workspace.windowList() : [];
for (var i = 0; i < list.length; i++) {
    var c = list[i];
    if (!c || c.deleted || !c.normalWindow || c.skipTaskbar) continue;
    var id = String(c.desktopFileName || c.resourceClass || "");
    var out = "";
    try { out = c.output ? String(c.output.name || "") : ""; } catch (e) {}
    var g = "";
    try { var fg = c.frameGeometry; g = fg ? [fg.x, fg.y, fg.width, fg.height].join(",") : "null"; } catch (e) { g = "err"; }
    var a1 = "err", a2 = "err";
    try { var r1 = workspace.clientArea(workspace.MaximizeArea, c); a1 = r1 ? [r1.x, r1.y, r1.width, r1.height].join(",") : "null"; } catch (e) { a1 = "throw"; }
    try { var r2 = workspace.clientArea(2, c.output, c.desktop); a2 = r2 ? [r2.x, r2.y, r2.width, r2.height].join(",") : "null"; } catch (e) { a2 = "throw"; }
    log("win", [id, out, "frame:" + g, "area-enum:" + a1, "area-num:" + a2,
                "maxSig:" + (typeof c.maximizedChanged), "fsSig:" + (typeof c.fullScreenChanged)].join(" | "));
}
```

- [ ] **Step 2: Cargarla en KWin y leer el resultado**

```bash
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.unloadScript caparazon-probe >/dev/null 2>&1
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.loadScript /tmp/opencode/kwin-cover-probe.js caparazon-probe
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.start
journalctl --user -b -n 200 -o cat _COMM=kwin_wayland | grep CAPARAZON_PROBE | tail -20
```

- [ ] **Step 3: Decidir y anotar**

Expected: al menos una línea `win=...` con `area-enum` distinto de `throw`; con una ventana maximizada abierta, `frame` y `area-enum` coinciden (o difieren ≤ 2 px). Si `area-enum` es `throw`, usar la variante numérica (`area-num`). Anotar en la tarea qué variante funcionó y limpiar el script del compositor:

```bash
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.unloadScript caparazon-probe >/dev/null 2>&1
rm -f /tmp/opencode/kwin-cover-probe.js
```

---

### Task 2: El puente KWin publica `covering` y el demonio lo persiste

**Files:**
- Modify: `integration/kwin/ezkudesktops/contents/code/main.js:37-126` (dentro de `push()` y sus helpers), `:173-193` (`watchClient`)
- Modify: `integration/bin/ezku-desktops-daemon.py:29` (estado inicial) y `:129-167` (rama `PushState`)
- Create: `tests/support/dock_covering_harness.js`
- Test: `tests/test_dock_covering.py`

**Interfaces:**
- Consumes: la variante de `clientArea` confirmada en Task 1.
- Produces: en el JSON de `PushState` una clave `covering` con forma `{"<outputName>": ["<appId>", …]}`; en el caché `~/.cache/ezku-desktops.json` la misma clave persistida (lista de como máximo 16 appIds por salida).

- [ ] **Step 1: Escribir el test y el harness (fallan)**

`tests/support/dock_covering_harness.js` carga el `main.js` real dentro de un `vm` con un KWin simulado, dispara los pushes y captura el último payload de `callDBus`. Escenarios mínimos y su `expected`:

```js
// Escenarios (id -> resultado esperado de payload.covering)
// "maximizada":   { "DP-1": ["org.kde.dolphin"] }
// "normal":       {}
// "pantalla-completa": { "DP-1": ["org.kde.dolphin"] }
// "otra-salida":  { "HDMI-1": ["org.kde.dolphin"] }
// "dialogo":      {}
// "cerrada":      {}
// "opcion-maximizar": 2   // el valor de ClientAreaOption que recibe clientArea
// "respaldo-numerico": 2  // con workspace.MaximizeArea = undefined
```

El stub de `workspace` debe aportar: `screens`, `desktops`, `currentDesktop`, `currentDesktopForScreen()`, `activeWindow`, `activeScreen`, `windowList()`, `stackingOrder`, `clientList()`, `clientArea(option, client)` (devuelve `client.maximizeArea` y guarda `option`), `MaximizeArea: 2`, y objetos con `.connect(){}` para `windowAdded`, `windowActivated`, `clientAdded`, `clientRemoved`, `windowRemoved`, `currentDesktopChanged`, `desktopsChanged`, `activeOutputChanged`, `activeWindowChanged`, `clientActivated`. Además `callDBus()` (guarda el payload), `console`, y un `QTimer` falso que sólo recuerda el callback. Cada ventana falsa necesita `desktopFileName`, `resourceClass`, `resourceName`, `caption`, `internalId`, `output: {name}`, `deleted`, `normalWindow`, `skipTaskbar`, `skipPager`, `desktopWindow`, `dock`, `desktop`, `desktops`, `onAllDesktops`, `fullScreen`, `frameGeometry`, `maximizeArea` y los `*Changed` con `.connect()`.

`tests/test_dock_covering.py` sigue el patrón de `tests/test_dock_entries.py`: ejecuta el harness con node, parsea el JSON y parametriza los casos (saltar con `pytest.skip` si no hay node).

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_covering.py -q`
Expected: FAIL (el payload no trae `covering`).

- [ ] **Step 3: Implementar en el script de KWin**

En `main.js`, añadir junto a `windowAppIds()`:

> Si la sonda de Task 1 mostró que la variante de dos argumentos lanza excepción,
> usar `workspace.clientArea(maximizeAreaOption(), c.output, c.desktop)` y
> ajustar el stub del harness para que acepte esa firma.

```js
// ClientAreaOption.MaximizeArea: el área que KWin le da a una ventana
// maximizada, ya descontadas las franjas que reservan los paneles.
function maximizeAreaOption() {
    try { if (workspace.MaximizeArea !== undefined) { return workspace.MaximizeArea; } } catch (e) {}
    return 2;
}

function coversOutput(c) {
    var full = false;
    try { full = !!c.fullScreen; } catch (e0) {}
    if (full) { return true; }
    try {
        var area = workspace.clientArea(maximizeAreaOption(), c);
        var g = c.frameGeometry;
        if (!area || !g) { return false; }
        return Math.abs(g.x - area.x) <= 2 && Math.abs(g.y - area.y) <= 2 &&
               Math.abs(g.width - area.width) <= 2 && Math.abs(g.height - area.height) <= 2;
    } catch (e) { return false; }
}

// Por salida: appIds de las ventanas que ocupan toda la pantalla.
function coveringOutputs() {
    var map = {};
    var list = windowList();
    for (var i = 0; i < list.length; i++) {
        var c = list[i];
        try {
            if (!c || c.deleted || !c.normalWindow || c.skipTaskbar) { continue; }
            if (!coversOutput(c)) { continue; }
            var outName = c.output ? String(c.output.name || "") : "";
            if (!outName) { continue; }
            var appId = String(c.desktopFileName || c.resourceClass || c.resourceName || "");
            if (!map[outName]) { map[outName] = []; }
            if (appId && map[outName].indexOf(appId) === -1) { map[outName].push(appId); }
        } catch (e) { continue; }
    }
    return map;
}
```

En `push()`, añadir al objeto que se serializa: `covering: coveringOutputs()`.

En `watchClient(c)`, añadir tres conexiones con el mismo patrón defensivo del resto:

```js
try { if (c.maximizedChanged && c.maximizedChanged.connect) { c.maximizedChanged.connect(push); } } catch (e) {}
try { if (c.fullScreenChanged && c.fullScreenChanged.connect) { c.fullScreenChanged.connect(push); } } catch (e) {}
try { if (c.frameGeometryChanged && c.frameGeometryChanged.connect) { c.frameGeometryChanged.connect(schedulePushSoon); } } catch (e) {}
```

Y arriba, junto a `settleTimer`, un debounce para las ráfagas de geometría (KWin emite `frameGeometryChanged` en cada paso de un redimensionado):

```js
var pushSoonTimer = null;
try {
    pushSoonTimer = new QTimer();
    pushSoonTimer.interval = 120;
    pushSoonTimer.singleShot = true;
    pushSoonTimer.timeout.connect(function () { push(); });
} catch (e) {}

function schedulePushSoon() {
    try { if (pushSoonTimer) { pushSoonTimer.start(); return; } } catch (e) {}
    push();
}
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_dock_covering.py -q`
Expected: PASS.

- [ ] **Step 5: Persistir en el demonio + test de contrato**

`integration/bin/ezku-desktops-daemon.py`: añadir `"covering": {}` al `state` inicial y, en la rama de `PushState` (junto a `occupiedPerOutput`):

```python
if isinstance(data.get("covering"), dict):
    state["covering"] = {
        str(k): [str(x) for x in v if isinstance(x, str)][:16]
        for k, v in data["covering"].items()
        if isinstance(k, str) and isinstance(v, list)
    }
```

Test en `tests/test_dock_covering.py` (inspección de fuente, como `tests/test_bar_icon_wiring.py`): leer `integration/bin/ezku-desktops-daemon.py` y comprobar que `state` arranca con `"covering": {}` y que la rama `PushState` asigna `state["covering"]` saneando listas.

- [ ] **Step 6: Ejecutar todo y commitear**

Run: `uv run pytest tests/test_dock_covering.py -q && uv run ruff check`
Expected: PASS y `All checks passed!`.

```bash
git add integration/kwin/ezkudesktops/contents/code/main.js \
        integration/bin/ezku-desktops-daemon.py \
        tests/support/dock_covering_harness.js tests/test_dock_covering.py
git commit -m "Dock inteligente: el puente KWin publica las ventanas que cubren la pantalla"
```

---

### Task 3: `DockSmartHide.js`, la lógica del dock

**Files:**
- Create: `modules/dock/DockSmartHide.js`
- Create: `tests/support/dock_smart_hide_harness.js`
- Test: `tests/test_dock_smart_hide.py`

**Interfaces:**
- Consumes: nada.
- Produces (usado por Tasks 4 y 5):
  - `isCovered(covering: object, screenName: string) -> boolean`
  - `stateFor(covered: boolean, pointerOnDock: boolean) -> "normal" | "hidden" | "revealed"`
  - `maskRect(state: string, metrics: {surfaceWidth, surfaceHeight, dockWidth, dockHeight, shadowPad, hotEdge}) -> {x, y, width, height}`
  - `dockOffset(state: string, metrics: {dockHeight, shadowPad}) -> number`
  - `exclusiveZone(covered: boolean, metrics: {dockHeight, bottomGap}) -> number`

- [ ] **Step 1: Escribir el harness con los casos (falla)**

`tests/support/dock_smart_hide_harness.js` carga `modules/dock/DockSmartHide.js` con `vm` (patrón de `dock_entries_harness.js`) y emite JSON. Métricas de referencia: `{surfaceWidth: 1920, surfaceHeight: 64, dockWidth: 360, dockHeight: 52, shadowPad: 12, hotEdge: 6, bottomGap: 0}`.

```js
// id -> {valor esperado}
// "cubierta":                  isCovered({"DP-1":["a"]}, "DP-1")           -> true
// "otra-pantalla":             isCovered({"DP-1":["a"]}, "HDMI-1")         -> false
// "sin-ventanas":              isCovered({}, "DP-1")                       -> false
// "lista-vacia":               isCovered({"DP-1":[]}, "DP-1")              -> false
// "sin-datos":                 isCovered(null, "DP-1")                     -> false
// "estado-normal":             stateFor(false, false)                      -> "normal"
// "estado-oculto":             stateFor(true, false)                       -> "hidden"
// "estado-revelado":           stateFor(true, true)                        -> "revealed"
// "fuera-de-pantalla-no-cuenta": stateFor(false, true)                     -> "normal"
// "mascara-normal":            maskRect("normal", m)                       -> {x:780,y:12,width:360,height:52}
// "mascara-oculta":            maskRect("hidden", m)                       -> {x:780,y:58,width:360,height:6}
// "mascara-revelada":          maskRect("revealed", m)                     -> {x:780,y:12,width:360,height:52}
// "offset-oculto":             dockOffset("hidden", m)                     -> 64
// "offset-normal":             dockOffset("normal", m)                     -> 0
// "offset-revelado":           dockOffset("revealed", m)                   -> 0
// "zona-normal":               exclusiveZone(false, m)                     -> 52
// "zona-cubierta":             exclusiveZone(true, m)                      -> 0
```

`tests/test_dock_smart_hide.py`: mismo patrón que `test_dock_entries.py` (node + `vm`, JSON a stdout, casos parametrizados).

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_smart_hide.py -q`
Expected: FAIL (no existe `DockSmartHide.js`).

- [ ] **Step 3: Implementar `modules/dock/DockSmartHide.js`**

Funciones top-level (sin `.pragma library`, como `DockEntries.js`), con comentario de cabecera en español explicando los tres estados:

```js
function isCovered(covering, screenName) {
    if (!covering || typeof covering !== "object") { return false; }
    var name = String(screenName || "");
    if (!name) { return false; }
    var list = covering[name];
    return !!(list && list.length > 0);
}

function stateFor(covered, pointerOnDock) {
    if (!covered) { return "normal"; }
    return pointerOnDock ? "revealed" : "hidden";
}

// La franja sensible (hidden) vive dentro del rectángulo del dock, así que al
// revelarse no se pierde el hover: 58..64 ⊂ 12..64.
function maskRect(state, metrics) {
    var x = Math.round((metrics.surfaceWidth - metrics.dockWidth) / 2);
    if (state === "hidden") {
        return { x: x, y: metrics.surfaceHeight - metrics.hotEdge,
                 width: metrics.dockWidth, height: metrics.hotEdge };
    }
    return { x: x, y: metrics.shadowPad, width: metrics.dockWidth, height: metrics.dockHeight };
}

function dockOffset(state, metrics) {
    return state === "hidden" ? metrics.dockHeight + metrics.shadowPad : 0;
}

function exclusiveZone(covered, metrics) {
    return covered ? 0 : metrics.dockHeight + metrics.bottomGap;
}
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_dock_smart_hide.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/dock/DockSmartHide.js tests/support/dock_smart_hide_harness.js tests/test_dock_smart_hide.py
git commit -m "Dock inteligente: logica de estados del dock en JavaScript"
```

---

### Task 4: La shell recibe `covering` (`ActiveWindowService` + `shell.qml`)

**Files:**
- Modify: `modules/bar/ActiveWindowService.qml:1-3` (imports), `:91-115` (FileView/poll)
- Modify: `shell.qml:341-350` (delegate `Dock`)
- Test: `tests/test_dock_covering_wiring.py`

**Interfaces:**
- Consumes: `covering` del caché (Task 2).
- Produces: `ActiveWindowService.covering` (objeto salida→appIds, `{}` si aún no hay dato); el delegate `Dock` recibe `covering`.

- [ ] **Step 1: Escribir el test de contrato (falla)**

`tests/test_dock_covering_wiring.py` (inspección de fuente, patrón `test_bar_icon_wiring.py`):

```python
def test_the_window_service_exposes_the_covering_map() -> None:
    contents = (MODULES / "bar" / "ActiveWindowService.qml").read_text(encoding="utf-8")
    assert "property var covering" in contents
    assert "desktopCacheAdapter.covering" in contents

def test_the_shell_passes_the_covering_map_to_each_dock() -> None:
    contents = (REPO / "shell.qml").read_text(encoding="utf-8")
    assert "covering: activeWindowService.covering" in contents
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_covering_wiring.py -q`
Expected: FAIL.

- [ ] **Step 3: Implementar**

`ActiveWindowService.qml`: al `JsonAdapter` del caché añadirle `property var covering: ({})`; y tras él:

```qml
// Salidas con una ventana maximizada o a pantalla completa (las publica el
// puente KWin en el caché). El dock decide con esto si apartarse.
readonly property var covering: desktopCacheAdapter.covering || ({})
```

Ampliar el respaldo de `desktopCachePoll` para recargar también mientras `covering` no haya llegado nunca (guardar un `property bool coveringSeen: false` que se pone a `true` cuando el adaptador trae un objeto no vacío).

`shell.qml`: en el delegate `Dock`, añadir `covering: activeWindowService.covering`.

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_dock_covering_wiring.py tests/test_theme_tokens.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/bar/ActiveWindowService.qml shell.qml tests/test_dock_covering_wiring.py
git commit -m "Dock inteligente: la shell recibe las salidas cubiertas"
```

---

### Task 5: El dock se oculta, se revela y vuelve (`Dock.qml` + `Theme.qml`)

**Files:**
- Modify: `theme/Theme.qml:54-66` (métricas y animación)
- Modify: `modules/dock/Dock.qml:87-105` (JsonAdapter `smartHide`), `:188-248` (anchos, `exclusiveZone`, `mask`, `hitArea`), `:259-277` (`reveal`/`frame`), `:270-406` (`frame`)
- Test: `tests/test_dock_smart_hide_qml.py`

**Interfaces:**
- Consumes: `DockSmartHide.*` (Task 3), `covering` (Task 4).
- Produces: `Dock.covered`, `Dock.smartState`, `Dock.pointerOnDock`, `Theme.dockHotEdge`, `Theme.dockHideGrace`.

- [ ] **Step 1: Escribir el test de contrato (falla)**

`tests/test_dock_smart_hide_qml.py` (inspección de fuente):

```python
def test_the_theme_declares_the_smart_hide_tokens() -> None:
    contents = THEME.read_text(encoding="utf-8")
    assert "property int dockHotEdge: 6" in contents
    assert "property int dockHideGrace: 250" in contents

def test_the_dock_uses_the_smart_hide_library() -> None:
    contents = DOCK.read_text(encoding="utf-8")
    assert 'import "DockSmartHide.js" as DockSmartHide' in contents
    assert "DockSmartHide.isCovered" in contents
    assert "DockSmartHide.stateFor" in contents
    assert "DockSmartHide.maskRect" in contents
    assert "DockSmartHide.dockOffset" in contents

def test_the_dock_releases_its_reserved_strip_when_covered() -> None:
    contents = DOCK.read_text(encoding="utf-8")
    assert "exclusiveZone: DockSmartHide.exclusiveZone(dock.covered, dock.metrics)" in contents

def test_the_dock_offers_a_switch_in_its_config() -> None:
    contents = DOCK.read_text(encoding="utf-8")
    assert "property bool smartHide: true" in contents
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_smart_hide_qml.py -q`
Expected: FAIL.

- [ ] **Step 3: Implementar en `Theme.qml`**

En "Métricas": `readonly property int dockHotEdge: 6` (comentario: franja sensible al borde inferior).
En "Animación": `readonly property int dockHideGrace: 250` (comentario: ms de gracia antes de volver a esconder).

- [ ] **Step 4: Implementar en `Dock.qml`**

Import: `import "DockSmartHide.js" as DockSmartHide`.

`JsonAdapter` de pines: añadir `property bool smartHide: true`.

Propiedades nuevas (junto a `windowAppIds`):

```qml
property var covering: ({})

// El puntero está sobre el dock (o sobre su franja sensible). El temporizador
// de gracia lo apaga al salir, para que no parpadee al rozar el borde.
property bool pointerOnDock: false

readonly property bool smartHideEnabled: pinsAdapter.smartHide !== false
readonly property bool covered: dock.smartHideEnabled
    && DockSmartHide.isCovered(dock.covering, dock.screen ? String(dock.screen.name) : "")
readonly property string smartState: DockSmartHide.stateFor(dock.covered, dock.pointerOnDock)

// Métricas que consume DockSmartHide (la superficie mide dockHeight+shadowPad).
readonly property var metrics: ({
    surfaceWidth: dock.width,
    surfaceHeight: dock.height,
    dockWidth: dock.dockWidth,
    dockHeight: Theme.dockHeight,
    shadowPad: Theme.shadowPad,
    hotEdge: Theme.dockHotEdge,
    bottomGap: dock.bottomGap
})
```

`exclusiveZone`: pasar de `Theme.dockHeight + dock.bottomGap` a:

```qml
exclusiveZone: DockSmartHide.exclusiveZone(dock.covered, dock.metrics)
```

`hitArea`: dejar de ser un rectángulo fijo y seguir `maskRect`, con el `HoverHandler` y el temporizador dentro:

```qml
Item {
    id: hitArea
    readonly property var rect: DockSmartHide.maskRect(dock.smartState, dock.metrics)
    x: rect.x
    y: rect.y
    width: rect.width
    height: rect.height

    HoverHandler {
        id: dockHover
        onHoveredChanged: {
            if (hovered) {
                hideGrace.stop();
                dock.pointerOnDock = true;
            } else {
                hideGrace.restart();
            }
        }
    }
}

Timer {
    id: hideGrace
    interval: Theme.dockHideGrace
    onTriggered: dock.pointerOnDock = false
}
```

`frame`: quitar `anchors.bottom: parent.bottom` (no se puede fijar `y` con el ancla puesta) y pasar a posición explícita, con el deslizamiento y el desvanecido:

```qml
Item {
    id: frame
    x: Math.round((parent.width - width) / 2)
    y: parent.height - height + DockSmartHide.dockOffset(dock.smartState, dock.metrics)
    width: dock.dockWidth + 2 * Theme.shadowPad
    height: dock.reveal * (Theme.dockHeight + Theme.shadowPad)
    clip: true
    opacity: dock.smartState === "hidden" ? 0 : (0.25 + 0.75 * dock.reveal)

    Behavior on y { NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Theme.dur; easing.type: Easing.OutCubic } }
    // …(el resto del contenido actual no cambia)
}
```

- [ ] **Step 5: Ejecutar los tests**

Run: `uv run pytest tests/test_dock_smart_hide_qml.py tests/test_theme_tokens.py tests/test_dock_smart_hide.py -q`
Expected: PASS (los tokens nuevos existen y la lógica JS sigue verde).

- [ ] **Step 6: Commit**

```bash
git add theme/Theme.qml modules/dock/Dock.qml tests/test_dock_smart_hide_qml.py
git commit -m "Dock inteligente: el dock se oculta, se revela y vuelve"
```

---

### Task 6: Documentar el comportamiento

**Files:**
- Modify: `README.md` (sección del dock, cerca de la línea 11)
- Test: `tests/test_dock_smart_hide_qml.py` (añadir un caso)

**Interfaces:**
- Consumes: nada.
- Produces: nada.

- [ ] **Step 1: Añadir el test de documentación (falla)**

```python
def test_the_readme_documents_the_smart_hide() -> None:
    contents = README.read_text(encoding="utf-8").lower()
    assert "se aparta" in contents or "se esconde" in contents
    assert "maximiz" in contents
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_smart_hide_qml.py -q`
Expected: FAIL.

- [ ] **Step 3: Escribir el apartado en el README**

En la lista de características, junto a "Dock real", añadir una viñeta: el dock **se aparta de las ventanas maximizadas** (libera su franja para que la ventana ocupe la pantalla), **reaparece al acercar el puntero al borde inferior** (y se puede usar encima de la ventana) y **vuelve a su sitio** al cerrar la ventana o quitar el maximizado. Mencionar que se desactiva con `"smartHide": false` en `~/.config/caparazon/dock.json`.

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_dock_smart_hide_qml.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/test_dock_smart_hide_qml.py
git commit -m "Dock inteligente: guia de uso en el README"
```

---

### Task 7: Verificación en vivo

**Files:**
- Modify: ninguno (sólo despliegue y comprobación manual)

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: confirmación de que el comportamiento funciona en la sesión real.

- [ ] **Step 1: Instalar el puente actualizado y recargarlo**

```bash
cd /home/ezku/Projects/caparazon-shell
install -m644 integration/kwin/ezkudesktops/contents/code/main.js \
  ~/.local/share/kwin/scripts/ezkudesktops/contents/code/main.js
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.unloadScript ezkudesktops >/dev/null 2>&1
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.loadScript \
  "$HOME/.local/share/kwin/scripts/ezkudesktops/contents/code/main.js" ezkudesktops
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.start
```

- [ ] **Step 2: Reiniciar la shell**

Reiniciar el proceso de Quickshell de la sesión (`quickshell -p /home/ezku/Projects/caparazon-shell`, o el que esté lanzado desde `~/.config/autostart/caparazon.desktop`).

- [ ] **Step 3: Comprobar el dato en el caché**

Con una ventana maximizada abierta:

```bash
python3 -c "import json;d=json.load(open('/home/ezku/.cache/ezku-desktops.json'));print(d.get('covering'))"
```

Expected: un dict con la salida (`DP-1`, `HDMI-A-1`, …) y al menos un appId; `{}` o ausente con todo sin maximizar.

- [ ] **Step 4: Comprobar el comportamiento**

1. Maximizar una ventana → el dock se desliza fuera y la ventana ocupa hasta el borde inferior.
2. Al acercar el puntero al borde inferior (donde estaba el dock) → el dock sube encima de la ventana y responde a clics (iconos, contador, menú contextual).
3. Al dejar de interactuar y apartar el puntero → el dock se vuelve a esconder solo.
4. Cerrar la ventana (o quitar el maximizado) → el dock vuelve a su sitio y reserva su franja.
5. Con una ventana maximizada en otro monitor → el dock de este monitor no se mueve.
6. Un diálogo o una ventana no maximizada → el dock no se esconde.

- [ ] **Step 5: Regresión**

Run: `uv run pytest -q && uv run ruff check`
Expected: PASS (≥ 351 tests) y `All checks passed!`.

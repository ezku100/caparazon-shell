# Plan — Dock auto-oculto con pin

Fecha: 2026-11-03
Diseño: `docs/superpowers/specs/2026-11-03-dock-autooculto-pin-design.md` (aprobado)

Sustituye a `2026-11-02-dock-inteligente.md`. El cambio de rumbo: el dock se oculta
**siempre** y un botón de pin lo ancla. Se elimina la detección de ventanas
maximizadas (`covering`), que en KWin 6.7.4 atribuye las ventanas al monitor
equivocado (`c.output.name` no coincide con `c.output.geometry`).

## Global Constraints

- Idioma del código, comentarios y docs: español.
- TDD: cada tarea escribe primero su test en rojo.
- Sin commits durante la ejecución (AGENTS.md: el commit se pide explícitamente).
- `uv run ruff check` y `uv run pytest -q` deben quedar limpios al final.
- No tocar el puente de escritorios más allá de quitar `covering`.

---

### Task 1: El puente deja de publicar `covering`

**Files:**
- Modify: `integration/kwin/ezkudesktops/contents/code/main.js`
- Modify: `integration/bin/ezku-desktops-daemon.py`
- Test: `tests/test_dock_bridge_has_no_covering.py` (nuevo)

- [ ] **Step 1: Test en rojo**

```python
"""El puente no publica 'covering': el dock ya no lo necesita."""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
BRIDGE = REPOSITORY_ROOT / "integration" / "kwin" / "ezkudesktops" / "contents" / "code" / "main.js"
DAEMON = REPOSITORY_ROOT / "integration" / "bin" / "ezku-desktops-daemon.py"


def test_the_bridge_does_not_publish_covering() -> None:
    """Sin detección de ventanas maximizadas el puente no manda ese campo."""
    assert "covering" not in BRIDGE.read_text(encoding="utf-8")


def test_the_daemon_does_not_store_covering() -> None:
    """El demonio tampoco lo persiste: no queda código muerto."""
    assert "covering" not in DAEMON.read_text(encoding="utf-8")
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_bridge_has_no_covering.py -q`
Expected: FAIL (2 failed).

- [ ] **Step 3: Quitar `covering` de `main.js`**

Borrar: `maximizeAreaOption()`, `sameRect()`, `coversOutput()`, `coveringOutputs()`,
el campo `covering: coveringOutputs()` del payload, el temporizador `geometryTimer` y
`schedulePushSoon()`, y las conexiones `maximizedChanged`, `fullScreenChanged` y
`frameGeometryChanged` de `watchClient`. Dejar el resto del puente intacto
(escritorios, ventana activa, apps por salida).

- [ ] **Step 4: Quitar `covering` del demonio**

Borrar el bloque que guarda `state["covering"]` en `PushState` y el saneado
correspondiente.

- [ ] **Step 5: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_dock_bridge_has_no_covering.py -q`
Expected: PASS (2 passed).

---

### Task 2: Fuera `covering` de la shell

**Files:**
- Modify: `modules/bar/ActiveWindowService.qml`
- Modify: `shell.qml`
- Modify: `modules/dock/Dock.qml` (sólo la parte de `covering`)
- Delete: `tests/test_dock_covering.py`, `tests/test_dock_covering_wiring.py`,
  `tests/support/dock_covering_harness.js`

- [ ] **Step 1: Test en rojo** (extender el test nuevo del Task 1)

```python
def test_the_shell_does_not_wire_covering() -> None:
    """La shell tampoco habla de 'covering'."""
    service = REPOSITORY_ROOT / "modules" / "bar" / "ActiveWindowService.qml"
    shell = REPOSITORY_ROOT / "shell.qml"
    assert "covering" not in service.read_text(encoding="utf-8")
    assert "covering" not in shell.read_text(encoding="utf-8")
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_bridge_has_no_covering.py -q`
Expected: FAIL.

- [ ] **Step 3: Quitar `covering`**

- `ActiveWindowService.qml`: borrar `readonly property var covering` y la propiedad
  `covering` del `JsonAdapter`; el poll sigue recargando el caché (no se toca).
- `shell.qml`: borrar la línea `covering: activeWindowService.covering`.
- `Dock.qml`: borrar `property var covering: ({})`.

- [ ] **Step 4: Borrar los tests y el harness de `covering`**

```bash
rm tests/test_dock_covering.py tests/test_dock_covering_wiring.py \
   tests/support/dock_covering_harness.js
```

- [ ] **Step 5: Ejecutar y ver que pasa**

Run: `uv run pytest -q`
Expected: PASS (menos los tests borrados; ninguno rojo).

---

### Task 3: Estados del dock con pin

**Files:**
- Modify: `modules/dock/DockSmartHide.js`
- Modify: `tests/support/dock_smart_hide_harness.js`
- Modify: `tests/test_dock_smart_hide.py`

- [ ] **Step 1: Reescribir el harness con los casos nuevos**

Casos (id → valor esperado):

| caso | llamada | esperado |
|------|---------|----------|
| `anclado` | `stateFor(true, false)` | `"anchored"` |
| `anclado-con-raton` | `stateFor(true, true)` | `"anchored"` |
| `oculto` | `stateFor(false, false)` | `"hidden"` |
| `revelado` | `stateFor(false, true)` | `"revealed"` |
| `mascara-anclada` | `maskRect("anchored", metrics)` | `{x:780,y:12,width:360,height:52}` |
| `mascara-oculta` | `maskRect("hidden", metrics)` | `{x:780,y:58,width:360,height:6}` |
| `mascara-revelada` | `maskRect("revealed", metrics)` | `{x:780,y:12,width:360,height:52}` |
| `desplazamiento-oculto` | `dockOffset("hidden", metrics)` | `64` |
| `desplazamiento-anclado` | `dockOffset("anchored", metrics)` | `0` |
| `zona-exclusiva-anclada` | `exclusiveZone(true, metrics)` | `52` |
| `zona-exclusiva-suelta` | `exclusiveZone(false, metrics)` | `0` |

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_smart_hide.py -q`
Expected: FAIL (el módulo todavía no conoce `anchored`).

- [ ] **Step 3: Reescribir `DockSmartHide.js`**

```javascript
// Estados del dock: anclado (con pin), revelado (el ratón encima) y oculto.
//
// El dock está oculto por defecto; el botón de pin lo deja anclado, visible y
// reservando su franja como el dock de siempre.

function stateFor(dockPinned, pointerOnDock) {
    if (dockPinned) {
        return "anchored";
    }
    return pointerOnDock ? "revealed" : "hidden";
}

// La franja que queda al apartar el dock cae dentro del rectángulo del dock
// (58..64 está dentro de 12..64), así que al revelarse no se pierde el ratón.
function maskRect(state, metrics) {
    var x = Math.round((metrics.surfaceWidth - metrics.dockWidth) / 2);
    if (state === "hidden") {
        return {
            x: x,
            y: metrics.surfaceHeight - metrics.hotEdge,
            width: metrics.dockWidth,
            height: metrics.hotEdge,
        };
    }
    return {
        x: x,
        y: metrics.shadowPad,
        width: metrics.dockWidth,
        height: metrics.dockHeight,
    };
}

// Distancia que baja el dock para salirse de la pantalla.
function dockOffset(state, metrics) {
    return state === "hidden" ? metrics.dockHeight + metrics.shadowPad : 0;
}

// Franja que el compositor le reserva: sólo cuando el dock está anclado.
function exclusiveZone(dockPinned, metrics) {
    return dockPinned ? metrics.dockHeight + metrics.bottomGap : 0;
}
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_dock_smart_hide.py -q`
Expected: PASS.

---

### Task 4: El dock lee el pin, muestra el botón y no se esconde con menús

**Files:**
- Modify: `modules/dock/Dock.qml`
- Modify: `tests/test_dock_smart_hide_qml.py`

- [ ] **Step 1: Tests en rojo**

```python
def test_the_dock_reads_the_pin_from_its_config() -> None:
    """El pin vive en dock.json y se llama dockPinned."""
    contents = DOCK.read_text(encoding="utf-8")
    assert "property bool dockPinned: false" in contents
    assert "dockPinned: dock.dockPinned" in contents


def test_the_dock_toggles_the_pin_and_saves_it() -> None:
    """Un clic alterna el pin y lo guarda en disco."""
    contents = DOCK.read_text(encoding="utf-8")
    assert "pinsAdapter.dockPinned = " in contents
    assert "pinsFile.writeAdapter()" in contents


def test_the_dock_shows_a_pin_button() -> None:
    """El botón de pin vive dentro del dock."""
    contents = DOCK.read_text(encoding="utf-8")
    assert "pin" in contents
    assert "togglePin" in contents


def test_the_dock_stays_while_a_menu_is_open() -> None:
    """Con un menú abierto el dock no se esconde."""
    contents = DOCK.read_text(encoding="utf-8")
    assert "menuOpen" in contents


def test_the_dock_uses_the_anchored_state() -> None:
    """Los estados vienen de la librería, con el pin como entrada."""
    contents = DOCK.read_text(encoding="utf-8")
    assert "DockSmartHide.stateFor(dock.dockPinned, dock.pointerOnDock)" in contents
    assert "DockSmartHide.exclusiveZone(dock.dockPinned, dock.metrics)" in contents
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_smart_hide_qml.py -q`
Expected: FAIL.

- [ ] **Step 3: Implementar en `Dock.qml`**

1. Sustituir `property bool smartHide: true` del `JsonAdapter` por
   `property bool dockPinned: false`.
2. Añadir `readonly property bool dockPinned: pinsAdapter.dockPinned === true`.
3. Cambiar `smartState` a
   `DockSmartHide.stateFor(dock.dockPinned, dock.pointerOnDock)` y borrar `covered`,
   `smartHideEnabled` y `property var covering`.
4. Cambiar `exclusiveZone` a
   `DockSmartHide.exclusiveZone(dock.dockPinned, dock.metrics)`.
5. Añadir `readonly property bool menuOpen`: `appMenu.visible || ...` (los menús que
   el dock abre: `appMenu`, `trayMenuState`, `secondMenuState`). Con `menuOpen` a
   `true` el `hideGrace` no oculta el dock.
6. Añadir el botón de pin: un `Rectangle`/`IconImage` con `icon.name: "pin"` (relleno
   si está anclado, contorno si no) dentro de la fila de iconos, con `TapHandler`
   que llama a `togglePin()`.
7. `togglePin()`: `pinsAdapter.dockPinned = !pinsAdapter.dockPinned;`
   `pinsFile.writeAdapter();`

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_dock_smart_hide_qml.py tests/test_theme_tokens.py tests/test_dock_smart_hide.py -q`
Expected: PASS.

---

### Task 5: Documentar

**Files:**
- Modify: `README.md`
- Test: `tests/test_dock_smart_hide_qml.py`

- [ ] **Step 1: Test en rojo**

```python
def test_the_readme_documents_the_auto_hide_and_the_pin() -> None:
    """El README explica el auto-ocultado y el pin."""
    contents = README.read_text(encoding="utf-8").lower()
    assert "oculto" in contents
    assert "pin" in contents
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_dock_smart_hide_qml.py -q`
Expected: FAIL.

- [ ] **Step 3: Escribir el apartado**

En la lista de características, junto a "Dock real": el dock está **oculto** y sube
al acercar el puntero al borde inferior (se puede usar encima de la ventana), y el
**botón de pin** lo deja **anclado**, visible y reservando su franja. El estado se
guarda en `~/.config/caparazon/dock.json` (`"dockPinned": true`).

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_dock_smart_hide_qml.py -q`
Expected: PASS.

---

### Task 6: Verificación en vivo

**Files:** ninguno (sólo despliegue y comprobación)

- [ ] **Step 1: Desplegar el puente y reiniciar la shell**

```bash
cd /home/ezku/Projects/caparazon-shell
install -m644 integration/kwin/ezkudesktops/contents/code/main.js \
  ~/.local/share/kwin/scripts/ezkudesktops/contents/code/main.js
install -m755 integration/bin/ezku-desktops-daemon.py ~/.local/bin/ezku-desktops-daemon.py
pkill -f ezku-desktops-daemon.py
bash ~/.local/bin/ezku-desktops-bootstrap.sh
```

- [ ] **Step 2: Reiniciar Quickshell**

```bash
pkill -f "quickshell -p /home/ezku/Projects/caparazon-shell"
setsid nohup quickshell -p /home/ezku/Projects/caparazon-shell -d >/tmp/opencode/quickshell.log 2>&1 </dev/null &
```

- [ ] **Step 3: Comprobar**

1. El dock arranca oculto (sin iconos en el borde inferior).
2. Al mover el puntero al borde inferior el dock sube y responde a los clics.
3. Al mover el puntero fuera se oculta solo (250 ms de gracia).
4. Con un menú abierto (clic derecho en un icono) el dock no desaparece.
5. El botón de pin alterna: anclado = visible y la ventana maximizada respeta su
   franja; suelto = vuelve a ocultarse.
6. Al reiniciar la shell, el pin conserva su valor (`dock.json`).

Capturas con `spectacle -b -n -o /tmp/opencode/estado.png -f` y recortes con `magick`.

---

### Task 7: Revisión final

- [ ] **Step 1: Suite completa**

Run: `uv run pytest -q && uv run ruff check`
Expected: PASS y `All checks passed!`.

- [ ] **Step 2: Repasar el diff contra el diseño**

Run: `git status --short && git diff --stat`
Expected: sólo los archivos del diseño; nada de `covering` en el repo.

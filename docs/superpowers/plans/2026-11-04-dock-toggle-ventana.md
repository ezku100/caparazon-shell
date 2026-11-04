# Plan — Dock: segunda pulsación minimiza o restaura

Fecha: 2026-11-04
Diseño: `docs/superpowers/specs/2026-11-04-dock-toggle-ventana-design.md`

## Global Constraints

- Idioma del código, comentarios y docs: español.
- TDD: la lógica se prueba con node contra un `workspace` falso, sin compositor.
- Sin commits durante la ejecución (el commit se pide explícitamente).
- `uv run pytest -q` y `uv run ruff check` limpios al final.
- El mecanismo de carga (`gdbus` + plantilla con marcadores) se conserva: es el
  que ya usa `KWinActiveTitle.js` y funciona en KWin 6.7.4.

---

### Task 1: La decisión vive en un script de KWin

**Files:**
- Create: `modules/bar/KWinWindowAction.js`
- Delete: `modules/bar/KWinFocusApp.js`
- Test: `tests/test_dock_window_action.py` + `tests/support/kwin_window_action_harness.js`

- [x] **Step 1: Test en rojo** — harness con `workspace` falso y escenarios
  (enfocar, minimizar, restaurar, pista de la shell, sin ventanas, varias
  ventanas, paneles ignorados, candidatos por app).
- [x] **Step 2: Ejecutar y ver que falla** (`node` no encontraba el script).

- [x] **Step 3: Script nuevo** — recibe los appIds candidatos separados por
  `|` y la pista de la app activa; decide:
  - ventana minimizada → `minimized = false` + `workspace.activeWindow`
  - app enfocada (`workspace.activeWindow` o la pista) → `minimized = true`
  - en otro caso → `workspace.activeWindow` (comportamiento de siempre)

- [x] **Step 4: Verificar en vivo** — sonda en KWin 6.7.4: `minimized` es
  escribible, el ciclo minimizar/restaurar funciona y el clic en un panel de
  Quickshell no cambia la ventana activa.

### Task 2: El dock pasa los candidatos y la app activa

**Files:**
- Modify: `modules/dock/Dock.qml`

- [x] **Step 1: Carcaza** — `test_the_dock_asks_kwin_for_the_window_action` en
  rojo (el `Process` apuntaba a `KWinFocusApp.js`).
- [x] **Step 2: Cablear** — `windowActionProcess` con `target` (candidatos de
  `targetIdsFor()` unidos por `|`) y `active` (`dock.activeAppId`). Sed con
  delimitador `@`. Si la acción anterior sigue en curso, se cancela y se
  relanza para no perder el clic.
- [x] **Step 3: Pasar el test completo.**

### Task 3: Documentación

**Files:**
- Modify: `README.md`

- [x] **Step 1:** describir el comportamiento del clic en "Dock real" y
  actualizar la lista de scripts de KWin.

### Task 4: Verificación final

- [ ] `uv run pytest -q` en verde.
- [ ] `uv run ruff check` limpio.
- [ ] En vivo: con una app enfocada, el icono la minimiza al segundo clic y la
      restaura al tercero; una app en segundo plano se enfoca al pulsarla.

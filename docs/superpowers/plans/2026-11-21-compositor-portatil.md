# Puerto a niri — backends de compositor + dotfile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que caparazon-shell funcione bajo niri ≥26.04 sin bifurcar el QML, vía un CLI único `caparazon-wm` con backends kwin/niri, más un `config.kdl` de niri con gaps, bordes, sombras, redondeo, animaciones y blur.

**Architecture:** CLI Python `integration/bin/caparazon-wm.py` con subcomandos estables (`detect`, `active-output`, `primary-output`, `workspaces`, `watch-workspaces`, `windows`, `watch-windows`, `window-action`, `logout`). El QML sólo invoca ese CLI; el CLI despacha a backend según detección. La lógica KWin existente (busctl, kscreen, script de acción) se mueve *dentro* del CLI sin cambiar su comportamiento. Parte B es un dotfile validado con `niri validate`, independiente de la Parte A.

**Tech Stack:** Python 3.11+ (subprocess + json), Quickshell/QML, pytest, node (harness KWin existente), niri 26.04 (`niri msg -j`, `niri validate`).

**Spec:** `docs/superpowers/specs/2026-11-21-compositor-portatil-design.md`

## Global Constraints

- Idioma del código, comentarios y docs: español.
- TDD: lógica del CLI con fixtures/fakes en PATH; lógica KWin sigue en el harness node existente.
- Sin commits durante la ejecución (el commit se pide explícitamente).
- `uv run pytest -q` y `uv run ruff check` limpios al final.
- No romper el comportamiento en KWin: los backends kwin replican hoy byte a byte las llamadas.
- Detección por invocación: `NIRI_SOCKET` → busctl KWin → `niri msg version` → fallback `kwin`.
- Shape JSON de `workspaces` idéntico al caché actual (`current`, `desktops[{pos,id,name}]`, `occupied`, `perOutput`, `focusedScreen`, `occupiedPerOutput`).
- El QML no contiene `org.kde.*`, `kscreen-doctor` ni `journalctl _COMM=kwin_wayland` al final de la Parte A (sólo viven tras el CLI).
- Ruff sigue con `include = ["tests/**/*.py", "modules/secondmenu/gcal.py"]` — no ampliar el alcance de lint al CLI salvo que se pida.
- Parte B: `niri validate -c` en verde; no tocar `~/.config/niri/config.kdl` si ya existiera sin respaldo.

## Review Focus

1. **Detección en sesión Plasma con niri instalado** — sin `NIRI_SOCKET`, `niri msg version` falla y no debe secuestrar la detección; esperado: `kwin`. → test: fake `niri` que falla + fake `busctl` que responde → `detect` = `kwin`.
2. **Detección dentro de niri sin KWin** — esperado: `niri` aunque `busctl` falle o no exista. → test: `NIRI_SOCKET` set → `niri`.
3. **Ruptura del ciclo del dock en KWin** — el segundo clic debe seguir minimizando. → test node existente (`test_dock_window_action.py`) en verde + test de que el CLI kwin sigue invocando `KWinWindowAction.js`.
4. **Pérdida de escritorios/ocupación** — `workspaces` debe mantener el shape que lee `WorkspacesService` (incl. `occupied`). → test de fixture JSON + assert de claves.
5. **`config.kdl` inválido** — un KDL mal formado no debe instalarse. → test: `niri validate -c` en el archivo del repo; paso de copia sólo si valida.

---

## PARTE A — CLI `caparazon-wm` y cableado QML

### Task 1: CLI con `detect` + `active-output` + `primary-output` (backends kwin/niri)

**Files:**
- Create: `integration/bin/caparazon-wm.py`
- Test: `tests/test_caparazon_wm.py`

**Interfaces:**
- Produces: ejecutable `caparazon-wm` con subcomandos `detect` (stdout `kwin|niri`), `active-output` (stdout nombre), `primary-output` (stdout nombre). Detect en proceso: función interna `detect_compositor(env, run) -> str` testeable con `run` inyectado.

- [ ] **Step 1: Test en rojo** — `tests/test_caparazon_wm.py`:
  - `test_detect_prefers_niri_socket`: env con `NIRI_SOCKET` → `niri`.
  - `test_detect_uses_kwin_when_bus_responde`: sin `NIRI_SOCKET`, fake `busctl` exit 0 → `kwin` (aunque fake `niri msg version` también funcione).
  - `test_detect_falls_back_to_niri`: sin `NIRI_SOCKET`, `busctl` falla, `niri msg version` ok → `niri`.
  - `test_detect_defaults_to_kwin`: ambos fallan → `kwin`.
  - `test_active_output_kwin`: fake `busctl` que imprime `s "DP-1"` → `DP-1`.
  - `test_active_output_niri`: fake `niri msg --json focused-output` con JSON `{"name":"HDMI-A-1"}` → `HDMI-A-1` (formato real a confirmar con `niri msg focused-output --help`/fixture del sistema; si el campo difiere, ajustar fixture y parser juntos).
  - `test_primary_output_kwin`: fake `kscreen-doctor` con JSON de prioridades → la de prioridad 1 (misma lógica que hoy en `ShellLayout.parsePrimary`).
  - `test_primary_output_niri`: primera salida enabled de `niri msg --json outputs`.
- [ ] **Step 2: Ejecutar y ver que falla** — `uv run pytest tests/test_caparazon_wm.py -v` → FAIL (módulo no existe).
- [ ] **Step 3: Implementar** `integration/bin/caparazon-wm.py`:
  - `#!/usr/bin/env python3`, `main(argv) -> int`.
  - `run(cmd) -> CompletedProcess` envoltorio (sustituible en tests con monkeypatch o PATH con fakes).
  - Backend kwin: `busctl --user call org.kde.KWin /KWin org.kde.KWin activeOutputName` (parseo `"…"` como en `shell.qml`); primary: `kscreen-doctor --json -o` + misma lógica de prioridad que `ShellLayout.qml:188-216`.
  - Backend niri: `niri msg --json focused-output` / `niri msg --json outputs`.
  - Instalar con `chmod +x`; los tests usan `python3 integration/bin/caparazon-wm.py …` o PATH con fakes.
- [ ] **Step 4: Verificar en verde** — `uv run pytest tests/test_caparazon_wm.py -v` → PASS.
- [ ] **Step 5: Commit** (sólo si el usuario lo pide).

### Task 2: Subcomandos `workspaces` y `watch-workspaces`

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_caparazon_wm.py` (añadir casos)

**Interfaces:**
- Consumes: `detect_compositor` del Task 1.
- Produces: `workspaces` → stdout JSON con claves `current, desktops, occupied, perOutput, focusedScreen, occupiedPerOutput`. `watch-workspaces` → imprime ese JSON una línea por evento hasta SIGTERM.

- [ ] **Step 1: Test en rojo**:
  - `test_workspaces_shape_matches_cache`: con fake backend (kwin o niri), el JSON tiene exactamente esas 6 claves; `desktops` es lista de `{pos,id,name}`.
  - `test_workspaces_niri_parses_fixture`: fixture `niri msg -j workspaces` + `niri msg -j windows` (campos reales: idx/name/output/window_count — confirmar con `niri msg --help` en sesión niri o docs IPC) → `occupied` = workspaces con `window_count > 0`; `current` = workspace activo.
  - `test_workspaces_kwin_wraps_virtual_desktop_manager`: fake `busctl` con el JSON de `desktops` y `current` de hoy → mismo shape de salida.
  - `test_watch_workspaces_emits_line_per_event`: con backend fake que escribe 2 eventos, stdout tiene 2 líneas JSON válidas.
- [ ] **Step 2: Ejecutar y ver que falla.**
- [ ] **Step 3: Implementar**:
  - kwin: replicar los dos `busctl … VirtualDesktopManager Get desktops/current` de `WorkspacesService.qml` + `dbus-monitor` (o event equivalente) para watch.
  - niri: `niri msg --json workspaces` + `niri msg --json windows`; watch vía `niri msg --json event-stream` filtrando eventos de workspaces/windows.
  - Unificar a `state_from_kwin(...)` / `state_from_niri(...)` → mismo dict.
- [ ] **Step 4: Verde** — `uv run pytest tests/test_caparazon_wm.py -v`.
- [ ] **Step 5: Commit** (si se pide).

### Task 3: Cablear `WorkspacesService.qml` al CLI

**Files:**
- Modify: `modules/bar/WorkspacesService.qml`
- Modify: `tests/…` — actualizar cualquier assert que exija `busctl`/`org.kde.KWin` en este archivo (grep en Step 1).

**Interfaces:**
- Consumes: `caparazon-wm workspaces` / `watch-workspaces` (Task 2).
- Produces: mismas propiedades de hoy: `desks`, `currentId`, `occupancyKnown`, `occupiedIds(screen)`, `screenCurrentId(screen)`, `screenFocused(screen)`, `refresh()`.

- [ ] **Step 1: Test rojo** — test de contrato (estilo carcaza del repo): el archivo contiene `"caparazon-wm"` y ya no contiene `org.kde.KWin` ni `dbus-monitor`. Correr pytest → FAIL.
- [ ] **Step 2: Implementar**:
  - `fetch`: `command: ["caparazon-wm", "workspaces"]` → parsea JSON a `queriedDesks` / `queriedCurrentId` (+ ocupación si se expone en la misma línea; si no, mantener FileView de caché como fallback igual que hoy).
  - `watcher`: `command: ["caparazon-wm", "watch-workspaces"]` con `SplitParser` → `refresh()`.
  - Conservar `FileView` + `stateAdapter` como respaldo cuando el CLI falle.
- [ ] **Step 3: Verde** — `uv run pytest -q` (los tests de display/dock no deben romperse).
- [ ] **Step 4: Commit** (si se pide).

### Task 4: `windows` + `watch-windows` y cablear `ActiveWindowService.qml`

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Modify: `modules/bar/ActiveWindowService.qml`
- Test: `tests/test_caparazon_wm.py`, test carcaza del servicio

**Interfaces:**
- Produces: `windows` → `{appId, title, appIds}`; `watch-windows` → una línea JSON con ese shape por cambio.
- El servicio conserva propiedades `appId`, `title`, `windowAppIds`.

- [ ] **Step 1: Test rojo** (CLI): fixture niri `focused-window` + `windows` → shape correcto; fake kwin → emula el JSON que hoy publica `KWinActiveTitle.js` por journal (o envuelve el mismo script vía el camino ya existente dentro del CLI).
- [ ] **Step 2: Test rojo** (QML): `ActiveWindowService.qml` contiene `caparazon-wm` y no `_COMM=kwin_wayland` / `KWinActiveTitle.js`.
- [ ] **Step 3: Implementar CLI** — niri: `niri msg --json focused-window` + `niri msg --json windows` (mapear `app_id`→`appId`, `title`); watch: `event-stream` filtrando `FocusedWindowChanged` / `WindowsChanged`. kwin: mantener la carga del script + lectura del flujo actual *dentro* del CLI (p. ej. el CLI emite el mismo JSON por stdout al detectar cambios vía journalctl o vía un pequeño push del script — preferir: el CLI hace de puente y el QML ya no ve journal).
- [ ] **Step 4: Implementar QML** — sustituir el `Process` de journal + `kwinLoader` por un único `watch-windows`.
- [ ] **Step 5: Verde** — `uv run pytest -q`.
- [ ] **Step 6: Commit** (si se pide).

### Task 5: `window-action` y cablear el dock

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Modify: `modules/dock/Dock.qml` (`windowActionProcess`)
- Test: `tests/test_dock_window_action.py` (actualizar carcaza), `tests/test_caparazon_wm.py`

**Interfaces:**
- Consumes: `KWinWindowAction.js` + harness node existentes (se conservan).
- Produces: `caparazon-wm window-action <active> <candidato|candidato…>` — mismo contrato de clic que hoy.

- [ ] **Step 1: Test rojo**:
  - Actualizar `test_the_dock_asks_kwin_for_the_window_action` → el dock invoca `caparazon-wm` + `window-action` (no más `gdbus` inline en el QML).
  - Test CLI kwin: con PATH fake, el subcomando termina en el bash/gdbus actual (o en llamada equivalente) y sigue usando `KWinWindowAction.js`.
  - Test CLI niri: con fixtures, unfocused app → `niri msg action focus-window --id <id>`; app ya enfocada → sin `close-window` (niri no tiene minimize en CLI: si no hay acción segura, salir 0 sin cerrar; documentado). Candidatos se resuelven por `app_id` desde `niri msg -j windows`.
- [ ] **Step 2: Ejecutar y ver que falla.**
- [ ] **Step 3: Implementar** — mover el `command` bash actual de `Dock.qml:173-191` al CLI (rama kwin); rama niri nueva.
- [ ] **Step 4: Cablear Dock.qml** — `command: ["caparazon-wm", "window-action", …]` conservando `target`/`active` y el reinicio si ya corre.
- [ ] **Step 5: Verde** — `uv run pytest -q` (incluye harness node completo).
- [ ] **Step 6: Commit** (si se pide).

### Task 6: `logout`, bootstrap por compositor, `ShellLayout` primary-output

**Files:**
- Modify: `integration/bin/caparazon-wm.py` (`logout`, usar `primary-output` desde fuera)
- Modify: `modules/bar/PowerMenu.qml` (`runAction` logout)
- Modify: `theme/ShellLayout.qml` (`probe` → `caparazon-wm primary-output`; conservar `parsePrimary` sólo si se queda el kscreen *dentro* del CLI — el QML sólo recibe el nombre)
- Modify: `integration/bin/ezku-desktops-bootstrap.sh` (cargar script KWin sólo si `detect` = `kwin`)
- Modify: `install.sh` (`install -m755 integration/bin/caparazon-wm.py "$BIN_DIR/caparazon-wm"`)
- Test: actualizar `tests/test_display_prefs.py` (`kscreen-doctor` → contrato `caparazon-wm`); tests de bootstrap/PowerMenu a contratos nuevos.

**Interfaces:**
- Consumes: `detect`, `primary-output` (Task 1).
- Produces: `logout` (kwin: `qdbus6 org.kde.Shutdown … logout`; niri: `niri msg action quit`); bootstrap no toca `org.kde.KWin` en niri.

- [ ] **Step 1: Test rojo** — carcazas: PowerMenu ya no contiene `org.kde.Shutdown`; ShellLayout contiene `caparazon-wm` y no `kscreen-doctor`; bootstrap contiene `detect`; `test_display_prefs` actualizado; CLI `logout` con fakes.
- [ ] **Step 2: Implementar** cambios en los 4 archivos + CLI.
- [ ] **Step 3: Instalar local** — `install -m755 … "$HOME/.local/bin/caparazon-wm"` (o correr tramo relevante de `install.sh`) y probar a mano en Plasma: `caparazon-wm detect` → `kwin`, `primary-output` → nombre real, menús abren en la pantalla correcta.
- [ ] **Step 4: Verde** — `uv run pytest -q` y `uv run ruff check`.
- [ ] **Step 5: Commit** (si se pide).

### Task 7: Verificación en vivo + README

**Files:**
- Modify: `README.md` (requisitos: quitar obligatoriedad de `kscreen-doctor` para niri; documentar `caparazon-wm` y niri ≥26.04)

- [ ] **Step 1: Plasma (regresión)** — barra, dock (ciclo min/restaurar), escritorios, menú de energía logout, pantalla activa de menús. Todo igual que antes.
- [ ] **Step 2: niri (si hay sesión disponible)** — `niri` con el dotfile de la Parte B: shell arranca, escritorios se ven, dock lista apps, clic enfoca, logout sale. Si no hay sesión niri en la máquina, dejar constancia en el README y dejar los tests de fixtures como cobertura.
- [ ] **Step 3: README** — actualizar lista de herramientas KDE y sección de compositor.

---

## PARTE B — dotfile niri (`config.kdl`)

> Independiente de la Parte A: se puede ejecutar solo.

### Task 8: `config.kdl` del repo + validación

**Files:**
- Create: `integration/niri/config.kdl` (fuente versionada en este repo; `install.sh` la copia a `~/.config/niri/config.kdl`)
- Test: `tests/test_niri_config.py`

**Interfaces:**
- Produces: KDL validado por `niri validate -c` en `integration/niri/config.kdl`.

- [ ] **Step 1: Test rojo** — `test_niri_config_validates`: `subprocess.run(["niri", "validate", "-c", "integration/niri/config.kdl"])` returncode 0 (skip si no hay `niri` en PATH — ya está en esta máquina). `test_niri_config_has_effects`: el archivo contiene `gaps`, `border`, `shadow`, `geometry-corner-radius`, `animations`, `background-effect`.
- [ ] **Step 2: Escribir el KDL** con exactamente estos bloques (valores pin del diseño; ajustar colores al acento del tema si se conoce, si no los default Material del repo):

```kdl
// Preferencias de sesión: bordes alrededor de ventanas que aceptan no-CSD.
prefer-no-csd

layout {
    gaps 12

    border {
        width 2
        radius 12
        active-color "#8ab4f8"
        inactive-color "#3c4043"
    }

    focus-ring {
        width 0
    }

    shadow {
        on
        softness 30
        spread 4
        offset x=0 y=6
        color "#00000070"
    }
}

animations {
    window-open { duration-ms 150; curve "ease-out-expo"; }
    window-close { duration-ms 120; curve "ease-out-quad"; }
    workspace-switch { spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001; }
}

window-rule {
    // Esquinas redondeadas coherentes con el border radius.
    geometry-corner-radius 12
}

// Blur tras las capas de la shell (PowerMenu / overlay).
// Namespaces a confirmar con `niri msg layers` en sesión niri.
layer-rule {
    match namespace="quickshell"
    background-effect {
        blur true
    }
}
```

  - Si `niri validate` rechaza algún campo (`radius` en border, `curve`, etc.), corregir contra `niri msg`/docs locales hasta validar — el test manda.
  - Si `niri msg layers` reporta namespaces distintas de `quickshell`, ajustar el `match` y el comentario.
- [ ] **Step 3: Verde** — `uv run pytest tests/test_niri_config.py -v`.
- [ ] **Step 4: Commit** (si se pide).

### Task 9: Instalación del dotfile + enlace a dotfiles

**Files:**
- Modify: `install.sh` (opcional: paso `install_niri_config` sólo si no existe destino)
- Modify: `README.md` (cómo instalar el dotfile de niri)
- `~/dotfiles/niri/config.kdl` (copiar/versionar según AGENTS.md regla 5)

- [ ] **Step 1: Copiar** — si `~/.config/niri/config.kdl` no existe, copiar desde `integration/niri/config.kdl`; si existe, **no sobreescribir** (avisar y ofrecer diff).
- [ ] **Step 2: Validar en destino** — `niri validate -c ~/.config/niri/config.kdl`.
- [ ] **Step 3: Dotfiles** — proponer al usuario versionar `integration/niri/config.kdl` y/o enlazarlo desde `~/dotfiles/niri/` (regla 5 AGENTS.md; no hacer `git add` sin confirmación).
- [ ] **Step 4: README** — sección “niri”: versión mínima 26.04, instalación del dotfile, nota de namespaces y de que el segundo clic del dock no minimiza en niri aún.

### Task 10: Verificación final

- [ ] `uv run pytest -q` en verde.
- [ ] `uv run ruff check` limpio.
- [ ] `niri validate -c integration/niri/config.kdl` (o la ruta elegida) exit 0.
- [ ] En Plasma: regresión visual y de dock sin cambios de comportamiento.
- [ ] (Si hay sesión niri) sesión con la shell + dotfile: gaps/bordes/animaciones/blur visibles; `caparazon-wm detect` → `niri`.

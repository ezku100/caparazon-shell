# Iconos de tema en la barra: plan de implementacion

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir los trece glifos Nerd Font de la barra a iconos del tema activo y quitar la dependencia de JetBrainsMono Nerd Font.

**Architecture:** Las cadenas de nombres viven en `modules/icons/BarIcons.js`, un modulo JavaScript puro que QML carga y que node ejecuta en los tests, igual que `IconNames.js` e `IconTheme.js`. Los cuatro QML de la barra sustituyen el `Text` con glifo por un `IconImage` colorizado con `MultiEffect`, alimentado por `IconResolver.firstOf(...)`.

**Tech Stack:** Quickshell 0.3.x (QML), Quickshell.Widgets (`IconImage`), QtQuick.Effects (`MultiEffect`), pytest + node para los tests.

**Spec:** `docs/superpowers/specs/2026-10-28-iconos-de-tema-design.md`

## Global Constraints

- Cero escapes de Nerd Font (`\u{F...}`) y cero usos de `Theme.fontIcon` en la shell al terminar.
- Cero rutas absolutas de iconos: todo por nombre, via `IconResolver`.
- Los tamanos actuales no cambian: 52 px (menu), 15 px (chip de audio), 16 px (perfil), 15 px (boton).
- Las cadenas de nombres deben resolver en Tela-dark, Colloid-Dark, Reversal-dark, breeze, breeze-dark, Adwaita y Papirus; la primera alternativa siempre existe en los siete.
- Commits en espanol sin tildes, prefijo `Area: descripcion`; rama `feature/iconos-de-tema`; merge `--no-ff` a `main`; push a `origin/main`.
- Calidad obligatoria antes de cada commit de entrega: `uv run pytest -q`, `uv run ruff check .`, `uv run basedpyright`.

## Review Focus

- Un tema sin ninguno de los nombres de la cadena: debe caer al generico, nunca a un icono vacio ni a una excepcion de QML.
- Un nivel de audio en el limite exacto (0.001, 0.40, 0.75): debe elegir el mismo icono que el codigo actual con glifos.
- Un `audioNode` nulo al arrancar: el chip existe antes de que Pipewire entregue el nodo; no debe romper la binding.
- Un perfil de energia desconocido o vacio: debe dibujar el icono de equilibrado, como hoy.
- Un tema que solo trae la variante `-symbolic` (Adwaita): debe resolver igual.

---

### Task 1: Modulo de cadenas y sus tests

**Files:**
- Create: `modules/icons/BarIcons.js`
- Create: `tests/support/bar_icons_harness.js`
- Create: `tests/test_bar_icons.py`

**Interfaces:**
- Consumes: nada.
- Produces: `sessionNames(action)` -> `string[]`; `powerButtonNames()` -> `string[]`; `volumeNames(muted, level, microphone)` -> `string[]`; `powerProfileNames(profile)` -> `string[]`.

- [ ] **Step 1: Escribir el harness con los escenarios**

Escenarios obligatorios, cada uno con su `id`: `session_lock`, `session_logout`, `session_shutdown`, `session_reboot`, `session_unknown_is_empty`, `power_button`, `volume_speaker_high`, `volume_speaker_medium`, `volume_speaker_low`, `volume_speaker_muted`, `volume_silenced_by_level`, `volume_microphone_on`, `volume_microphone_muted`, `profile_saver`, `profile_balanced`, `profile_performance`, `profile_unknown_is_balanced`, `every_chain_starts_with_a_known_name`, `every_chain_is_a_copy`.

- [ ] **Step 2: Ejecutarlo y comprobar que falla**

Run: `node tests/support/bar_icons_harness.js`
Expected: falla al cargar `modules/icons/BarIcons.js` (no existe).

- [ ] **Step 3: Implementar `modules/icons/BarIcons.js`**

Tablas y funciones segun D1 del spec; devolver siempre copias con `slice()`.

- [ ] **Step 4: Ejecutarlo y comprobar que pasa**

Run: `node tests/support/bar_icons_harness.js`
Expected: JSON con todos los casos en `ok: true`.

- [ ] **Step 5: Commit**

```bash
git add modules/icons/BarIcons.js tests/support/bar_icons_harness.js tests/test_bar_icons.py
git commit -m "Iconos: cadenas de nombres de la barra"
```

### Task 2: Contrato del cableado de los cuatro QML

**Files:**
- Create: `tests/test_bar_icon_wiring.py`

**Interfaces:**
- Consumes: los nombres de funcion de Task 1.
- Produces: las aserciones que Tasks 3-6 deben satisfacer.

- [ ] **Step 1: Escribir el test de contrato y comprobarlo en rojo**

Comprueba, por fichero: ausencia de `\u{F`, ausencia de `Theme.fontIcon`, presencia de `IconResolver.firstOf` y de `BarIcons.`. Ademas: `theme/Theme.qml` sin `fontIcon`, `README.md` sin `Nerd`, `install.sh` sin `require_nerd_font`.

Run: `uv run pytest tests/test_bar_icon_wiring.py -q`
Expected: FAIL en los siete ficheros (aun tienen glifos o la funcion).

- [ ] **Step 2: Commit del test en rojo**

```bash
git add tests/test_bar_icon_wiring.py
git commit -m "Iconos: contrato del cableado de la barra"
```

### Task 3: Chip de audio

**Files:**
- Modify: `modules/bar/VolumeChip.qml:29-34`, `:106-112`

**Interfaces:**
- Consumes: `BarIcons.volumeNames(muted, level, microphone)`, `IconResolver.firstOf(names)`.
- Produces: nada para otras tareas.

- [ ] **Step 1: Importar lo que falta**

`Quickshell.Widgets`, `QtQuick.Effects`, `../icons` y `"../icons/BarIcons.js" as BarIcons`.

- [ ] **Step 2: Sustituir `iconGlyph` por `iconSource`**

`readonly property string iconSource: IconResolver.firstOf(BarIcons.volumeNames(root.muted, root.level, root.microphone))`.

- [ ] **Step 3: Sustituir el `Text` por `IconImage` de 15 px con `MultiEffect`**

`colorization: 1.0`, `colorizationColor: root.muted ? Theme.textDim : Theme.text`.

- [ ] **Step 4: Verificar el contrato y la carga**

Run: `uv run pytest tests/test_bar_icon_wiring.py -q`
Expected: sigue fallando por los otros tres ficheros; VolumeChip ya cumple.

### Task 4: Menu de sesion

**Files:**
- Modify: `modules/bar/PowerMenu.qml:228-233`, `:340-355`

**Interfaces:**
- Consumes: `BarIcons.sessionNames(action)`, `IconResolver.firstOf(names)`.
- Produces: nada.

- [ ] **Step 1: Cambiar el modelo del `Repeater`**

Cada entrada pasa a `{ key: "lock", delay: 0 }` y el icono se resuelve con `BarIcons.sessionNames(modelData.key)`.

- [ ] **Step 2: Sustituir el `Text` por `IconImage` de 52 px colorizado**

`property color iconColor` en el delegado con `Behavior on color { ColorAnimation { duration: Theme.durFast } }`, y `MultiEffect.colorizationColor: action.iconColor`.

- [ ] **Step 3: Verificar**

Run: `uv run pytest tests/test_bar_icon_wiring.py -q`
Expected: PowerMenu ya cumple; quedan PowerProfile y PowerButton.

### Task 5: Perfil de energia y boton

**Files:**
- Modify: `modules/bar/PowerProfile.qml:31-35`, `:91-114`
- Modify: `modules/bar/PowerButton.qml:38-44`

**Interfaces:**
- Consumes: `BarIcons.powerProfileNames(profile)`, `BarIcons.powerButtonNames()`, `IconResolver.firstOf(names)`.
- Produces: nada.

- [ ] **Step 1: PowerProfile sin glifo**

Se borran `glyph` y el `Text`; queda un solo `IconImage` de 16 px con `IconResolver.firstOf(BarIcons.powerProfileNames(root.displayProfile))` y el color actual.

- [ ] **Step 2: PowerButton sin glifo**

`IconImage` de 15 px con `IconResolver.firstOf(BarIcons.powerButtonNames())` y `Theme.text`.

- [ ] **Step 3: Verificar**

Run: `uv run pytest tests/test_bar_icon_wiring.py -q`
Expected: PASS en los cuatro QML; siguen en rojo las aserciones de Theme, README e install.sh.

### Task 6: Fuera la dependencia de Nerd Font

**Files:**
- Modify: `theme/Theme.qml:70`
- Modify: `README.md:39-44`
- Modify: `install.sh:52-60`, `:274`

- [ ] **Step 1: Borrar `fontIcon` de `Theme.qml`**

- [ ] **Step 2: Quitar el requisito del README y `require_nerd_font` del instalador (definicion y llamada)**

- [ ] **Step 3: Verificar todo**

Run: `uv run pytest -q && uv run ruff check . && uv run basedpyright`
Expected: todo en verde.

- [ ] **Step 4: Commit**

```bash
git add theme/Theme.qml README.md install.sh modules/bar/PowerMenu.qml modules/bar/VolumeChip.qml modules/bar/PowerProfile.qml modules/bar/PowerButton.qml
git commit -m "Iconos: la barra usa iconos de tema y ya no necesita Nerd Font"
```

### Task 7: Verificacion en vivo y entrega

**Files:**
- Modify: `README.md` solo si la captura revela algo que documentar.

- [ ] **Step 1: Capturar antes/despues y comprobar el log**

Run: `systemctl --user restart app-caparazon@autostart.service` y capturar con `spectacle -b -n -o`; revisar `/run/user/1000/quickshell/by-id/<id>/log.qslog`.
Expected: 0 errores QML, iconos visibles, hover cambia el color.

- [ ] **Step 2: Merge y push**

```bash
git merge --no-ff feature/iconos-de-tema -m "Iconos: iconos de tema en toda la barra"
git push origin main
```

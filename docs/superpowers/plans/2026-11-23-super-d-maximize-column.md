# Super+D Maximiza Columna en Niri Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hacer que `Super+D` maximice la columna activa en niri y deje de abrir el menú de Caparazón.

**Architecture:** Se mueve el bind de `Mod+D` fuera de la sección de menús y se asigna a la acción nativa `maximize-column` de niri 26.04, tanto en la config instalada como en la copia versionada del repo. El contrato se fija con un test de pytest sobre la config del repo; la config instalada se cubre con validación CLI, grep de invariantes y recarga en vivo. No se toca QML, KDE ni la shell.

**Tech Stack:** niri 26.04 (KDL), pytest, ruff, `niri validate`, `niri msg action load-config-file`.

**Spec:** `docs/superpowers/specs/2026-11-23-super-d-maximize-column-design.md`

## Global Constraints

- Responder en español.
- TDD estricto: test rojo antes del cambio de comportamiento.
- CLI como puerta de validación/recarga: `niri validate` y `niri msg ...`, sin QML escribiendo ficheros.
- Sin commits salvo petición explícita.
- Sin comprobaciones visuales ni interrumpir el mouse sin permiso explícito.
- No afectar el funcionamiento de la shell con KDE.
- Trabajo directo sin subagentes premium, según `AGENTS.md`.

## Review Focus

- Un `Mod+D` duplicado aún abre el menú: cubierto por la aserción de ausencia del bind viejo.
- `Mod+Space` pierde el menú principal: cubierto por la aserción de presencia del bind de menú.
- `maximize-column` no existe en esta versión de niri: cubierto por `niri validate`.
- La config instalada diverge de la versionada: cubierto por grep en ambos archivos.
- niri sigue usando la config vieja en memoria: cubierto por recarga vía IPC.
- `Mod+F` deja de ser pantalla completa: cubierto por grep en la config instalada.

---

### Task 1: Contrato y config versionada

**Files:**
- Modify: `tests/test_niri_binds.py`
- Modify: `integration/niri/config.kdl`

**Interfaces:**
- Consumes: `CONFIG` (`Path` a `integration/niri/config.kdl`) y el estilo existente de tests de texto en `tests/test_niri_binds.py`.
- Produces: `test_niri_config_maximizes_column_with_meta_d`, que fija el nuevo bind, la ausencia del bind anterior y la permanencia de `Mod+Space`.

- [x] **Step 1: Write the failing test**

Agregar en `tests/test_niri_binds.py`:

```python
def test_niri_config_maximizes_column_with_meta_d() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    assert "Mod+D { maximize-column; }" in contents
    assert 'Mod+D { spawn "caparazon-shell-ipc" "menu" "toggle"; }' not in contents
    assert 'Mod+Space { spawn "caparazon-shell-ipc" "menu" "toggle"; }' in contents
```

- [x] **Step 2: Run test to verify it fails**

Run: `./.venv/bin/python -m pytest tests/test_niri_binds.py::test_niri_config_maximizes_column_with_meta_d -q`
Expected: FAIL en `assert "Mod+D { maximize-column; }" in contents`.

- [x] **Step 3: Replace the repo bind**

En `integration/niri/config.kdl`:
- Quitar `    Mod+D { spawn "caparazon-shell-ipc" "menu" "toggle"; }` de la sección `// --- Menús de Caparazón ---`.
- Agregar `    Mod+D { maximize-column; }` en `// --- Ventanas ---`, justo después de `Mod+Q`.

- [x] **Step 4: Run test to verify it passes**

Run: `./.venv/bin/python -m pytest tests/test_niri_binds.py::test_niri_config_maximizes_column_with_meta_d -q`
Expected: PASS.

### Task 2: Config instalada y recarga en vivo

**Files:**
- Modify: `/home/ezku/.config/niri/config.d/70-binds.kdl`

**Interfaces:**
- Consumes: el bind exacto `Mod+D { maximize-column; }` de Task 1.
- Produces: config instalada con el mismo contrato y niri recargado sin reiniciar la sesión.

- [x] **Step 1: Apply the installed config change**

En `/home/ezku/.config/niri/config.d/70-binds.kdl`:
- Quitar `    Mod+D { spawn "caparazon-shell-ipc" "menu" "toggle"; }` de `// ── Menús y sesión de Caparazón ──`.
- Agregar `    Mod+D { maximize-column; }` en `// ── Ventana ──`, justo después de `Mod+F`.
- Actualizar el encabezado para que ya no describa `Mod+D` como atajo de Caparazón:

```kdl
// Base: los atajos de Caparazón (Mod+Space, menús, sesión) y la
// maximización de columna de niri, más los de ventana/escritorio de iNiR
// que no chocan. Ojo con la inversión de flechas:
// aquí Mod+flechas mueve la ventana y Mod+Ctrl+flechas mueve el foco.
```

- [x] **Step 2: Validate installed config**

Run: `niri validate`
Expected: exit 0 y salida vacía o `config is valid`, sin errores.

- [x] **Step 3: Check invariants in installed config**

Run:

```bash
grep -F 'Mod+D { maximize-column; }' /home/ezku/.config/niri/config.d/70-binds.kdl
! grep -F 'Mod+D { spawn "caparazon-shell-ipc" "menu" "toggle"; }' /home/ezku/.config/niri/config.d/70-binds.kdl
grep -F 'Mod+Space { spawn "caparazon-shell-ipc" "menu" "toggle"; }' /home/ezku/.config/niri/config.d/70-binds.kdl
grep -F 'Mod+F { fullscreen-window; }' /home/ezku/.config/niri/config.d/70-binds.kdl
```

Expected: el nuevo bind, `Mod+Space` y `Mod+F` presentes; el bind viejo de `Mod+D` ausente.

- [x] **Step 4: Reload niri config in place**

Run: `niri msg action load-config-file --path /home/ezku/.config/niri/config.kdl`
Expected: exit 0. No hacer comprobación visual ni mover el mouse.

### Task 3: Verificación completa

**Files:** ninguno.

**Interfaces:**
- Consumes: cambios de Task 1 y Task 2.
- Produces: evidence de que el cambio está limpio y no rompe la suite existente.

- [x] **Step 1: Full pytest suite**

Run: `./.venv/bin/python -m pytest -q`
Expected: `803 passed, 1 skipped` (802 previos + 1 nuevo test).

- [x] **Step 2: Lint del test**

Run: `./.venv/bin/python -m ruff check tests/test_niri_binds.py`
Expected: limpio.

- [x] **Step 3: Diff whitespace check**

Run: `git -C /home/ezku/Projects/caparazon-shell diff --check`
Expected: salida vacía, exit 0.

- [x] **Step 4: Validate both KDL configs**

Run:

```bash
niri validate
niri validate -c /home/ezku/Projects/caparazon-shell/integration/niri/config.kdl
```

Expected: ambas válidas, exit 0.

- [x] **Step 5: No commit**

No ejecutar `git add`, `git commit` ni `git push`.

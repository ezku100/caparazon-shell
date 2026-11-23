# Niri Configs Layout and Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reordenar **Niri configs** con Monitores arriba, Teclado en medio e Iconos/Cursor abajo; plegar la lista de resoluciones; y persistir el idioma de teclado en el config de niri mediante un subcomando nuevo del CLI.

**Architecture:** El CLI `caparazon-wm` sigue siendo la única puerta al sistema: lee/escribe `layout` y `variant` en el bloque `xkb` del fichero que aporta el valor efectivo, valida contra un catálogo curado y recarga niri. `KeyboardLayoutPanel.qml` sólo consume el JSON del CLI y envía `--set`. `NiriConfigsPanel.qml` mantiene un único `Flickable` y compone Monitores/Teclado/Selector de temas como secciones hermanas.

**Tech Stack:** Python 3 stdlib en `integration/bin/caparazon-wm.py`; QML/QtQuick + Quickshell en `modules/secondmenu/`; pytest, ruff, qmllint, niri 26.04.

**Spec:** `docs/superpowers/specs/2026-11-22-niri-configs-layout-keyboard-design.md`

## Global Constraints

- Español en mensajes, errores y texto visible.
- Sin commits salvo petición explícita.
- TDD estricto: tests primero, implementación después.
- Sin delegación a agentes premium; trabajo directo con el modelo actual.
- Ejecución nativa: pytest, qmllint, ruff y verificación con CLI real.
- El CLI es la única puerta al sistema.
- No se debe afectar el funcionamiento de la shell con KDE.
- No tocar `40-environment.kdl`, `50-startup.kdl`, `~/.config/autostart` ni archivos de KDE.
- No exponer `options`, `model`, `rules` ni `file` de xkb en la UI.
- No crear un segundo `Flickable`, `GridView` interactivo ni usar `QtQuick.Controls`.
- No automatizar comprobaciones visuales con mouse/capturas sin permiso explícito.

## Review Focus

- `latam` es un layout propio, no una variante de `es`: pinned en Task 1, `test_catalog_groups_spanish_latin_america_as_a_layout`.
- Un `variant` previo debe desaparecer al elegir una opción sin variante: pinned en Task 2, `test_set_removes_a_stale_variant`.
- Comentarios de ejemplo (`// layout "us,es"`) no deben leerse como configuración efectiva: pinned en Task 2, `test_read_ignores_commented_xkb_entries`.
- Fallar la recarga no debe dejar la UI creyendo que aplicó: pinned en Task 2, `test_apply_reports_reload_failure_after_writing`.
- QML no debe escribir config ni llamar a niri: pinned en Task 3, `test_keyboard_panel_does_not_talk_to_the_system`; Task 4, `test_wrapper_does_not_talk_to_the_system`.
- La lista de resoluciones debe quedar cerrada por defecto y no crear scroll propio: pinned en Task 5, `test_resolutions_are_collapsed_by_default` y `test_monitors_panel_has_no_nested_scroll`.

---

### Task 1: Catálogo y estado del teclado en el CLI

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_keyboard_layout_cli.py`

**Interfaces:**
- Consumes: `niri_config_path()`, `_kdl_lines_in_load_order()`, `reload_niri_config()` ya existentes.
- Produces:
  - `KEYBOARD_LAYOUTS: Final[tuple[dict[str, Any], ...]]`: catálogo agrupado por idioma con `label` y `options` de `{layout, variant, label}`.
  - `DEFAULT_KEYBOARD_LAYOUT: Final[str] = "us"`.
  - `KeyboardLayoutState`: dataclass frozen/slots con `layout: str`, `variant: str`, `label: str`, `configured: bool`, `languages: tuple[dict[str, Any], ...]` y `to_json() -> str`.
  - `keyboard_layout_catalog() -> tuple[dict[str, Any], ...]`.
  - `keyboard_layout_label(layout: str, variant: str) -> str`.
  - `keyboard_layout_known(layout: str, variant: str) -> bool`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_keyboard_layout_cli.py` con el cargador del CLI. Escribe estos tests:

```python
def test_catalog_groups_spanish_latin_america_as_a_layout() -> None:
    cli = _load_cli()
    languages = cli.keyboard_layout_catalog()
    spanish = next(item for item in languages if item["label"] == "Español")
    assert {"layout": "es", "variant": "", "label": "España"} in spanish["options"]
    assert {"layout": "latam", "variant": "", "label": "Latinoamérica"} in spanish["options"]


def test_catalog_covers_the_common_languages() -> None:
    cli = _load_cli()
    labels = [item["label"] for item in cli.keyboard_layout_catalog()]
    assert labels == ["Español", "Inglés", "Portugués", "Francés", "Alemán", "Italiano", "Japonés"]


def test_keyboard_layout_label_uses_the_catalog() -> None:
    cli = _load_cli()
    assert cli.keyboard_layout_label("latam", "") == "Español · Latinoamérica"
    assert cli.keyboard_layout_label("us", "intl") == "Inglés · EE. UU., internacional"
    assert cli.keyboard_layout_label("xx", "yy") == "Personalizada: xx/yy"


def test_keyboard_layout_known_requires_an_exact_catalog_match() -> None:
    cli = _load_cli()
    assert cli.keyboard_layout_known("es", "")
    assert not cli.keyboard_layout_known("es", "latam")
    assert not cli.keyboard_layout_known("xx", "")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tests/test_keyboard_layout_cli.py -v`

Expected: FAIL with `AttributeError` for `keyboard_layout_catalog`.

- [ ] **Step 3: Implement the catalog and state**

Implementa los nombres de la Interfaces block en `caparazon-wm.py`, junto a la sección de cursor. `keyboard_layout_label` usa `id · opción` para combinaciones conocidas y `Personalizada: layout/variant` en caso contrario; si `variant` está vacío, `Personalizada: layout` alcanza.

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tests/test_keyboard_layout_cli.py -v`

Expected: PASS.

- [ ] **Step 5: No commit**

No ejecutar `git commit`.

### Task 2: Lectura, escritura y apply del teclado

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_keyboard_layout_cli.py`

**Interfaces:**
- Consumes: Task 1; `_kdl_brace_delta()` existente.
- Produces:
  - `_strip_kdl_comment(line: str) -> str`.
  - `read_niri_keyboard_layout(text: str) -> tuple[str, str]`.
  - `read_keyboard_layout_file(path: Path) -> tuple[str, str]`.
  - `_find_keyboard_layout_file(path: Path) -> Path | None`.
  - `set_niri_keyboard_layout(text: str, layout: str, variant: str) -> str`.
  - `write_keyboard_layout(layout: str, variant: str) -> Path`.
  - `keyboard_layout_state() -> KeyboardLayoutState`.
  - `keyboard_layout_apply(layout: str, variant: str) -> int`.
  - `main()` acepta `keyboard-layout` y `keyboard-layout --set <layout> [variant]`.

- [ ] **Step 1: Write the failing tests**

Agrega a `tests/test_keyboard_layout_cli.py`:

```python
def test_read_ignores_commented_xkb_entries() -> None:
    cli = _load_cli()
    text = (
        "input {\n"
        "    keyboard {\n"
        "        xkb {\n"
        '            // layout "us,es"\n'
        '            layout "es"\n'
        '            variant "winkeys"\n'
        "        }\n"
        "    }\n"
        "}\n"
    )
    assert cli.read_niri_keyboard_layout(text) == ("es", "winkeys")


def test_read_keyboard_layout_file_uses_the_last_included_value(
    tmp_path: Path,
) -> None:
    cli = _load_cli()
    config_dir = tmp_path / "niri"
    config_dir.mkdir()
    (config_dir / "config.kdl").write_text(
        'include "config.d/10-input.kdl"\n'
        "input {\n    keyboard {\n        xkb {\n"
        '            layout "fr"\n'
        "        }\n    }\n}\n",
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    (config_dir / "config.d" / "10-input.kdl").write_text(
        "input {\n    keyboard {\n        xkb {\n"
        '            layout "de"\n'
        "        }\n    }\n}\n",
        encoding="utf-8",
    )
    assert cli.read_keyboard_layout_file(config_dir / "config.kdl") == ("fr", "")


def test_set_updates_layout_variant_and_keeps_options(tmp_path: Path) -> None:
    cli = _load_cli()
    text = (
        "input {\n"
        "    keyboard {\n"
        "        xkb {\n"
        '            layout "us"\n'
        '            options "compose:ralt,ctrl:nocaps"\n'
        "        }\n"
        "        repeat-delay 250\n"
        "    }\n"
        "}\n"
    )
    updated = cli.set_niri_keyboard_layout(text, "us", "intl")
    assert 'layout "us"' in updated
    assert 'variant "intl"' in updated
    assert 'options "compose:ralt,ctrl:nocaps"' in updated
    assert "repeat-delay 250" in updated


def test_set_removes_a_stale_variant() -> None:
    cli = _load_cli()
    text = (
        "xkb {\n"
        '    layout "us"\n'
        '    variant "intl"\n'
        '    options "ctrl:nocaps"\n'
        "}\n"
    )
    updated = cli.set_niri_keyboard_layout(text, "es", "")
    assert 'layout "es"' in updated
    assert "variant" not in updated
    assert 'options "ctrl:nocaps"' in updated


def test_set_creates_the_xkb_block_when_missing() -> None:
    cli = _load_cli()
    text = "input {\n    keyboard {\n        repeat-delay 250\n    }\n}\n"
    updated = cli.set_niri_keyboard_layout(text, "latam", "")
    assert "xkb {" in updated
    assert 'layout "latam"' in updated
    assert "repeat-delay 250" in updated
```

Agrega tests de CLI con `_run_cli`, entorno aislado y `FAKE_NIRI_RELOAD` de `test_caparazon_wm.py` (cópialos localmente):

```python
def test_cli_reports_the_current_keyboard_layout(tmp_path: Path) -> None:
    env = _keyboard_env(tmp_path)
    config_dir = Path(env["XDG_CONFIG_HOME"]) / "niri"
    config_dir.mkdir(parents=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/10-input.kdl"\n', encoding="utf-8"
    )
    (config_dir / "config.d").mkdir()
    (config_dir / "config.d" / "10-input.kdl").write_text(
        "input {\n    keyboard {\n        xkb {\n"
        '            layout "es"\n'
        "        }\n    }\n}\n",
        encoding="utf-8",
    )
    result = _run_cli(["keyboard-layout"], env_extra=env)
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["layout"] == "es"
    assert payload["label"] == "Español · España"
    assert payload["configured"] is True
    assert payload["languages"][0]["label"] == "Español"


def test_cli_reports_default_when_there_is_no_config(tmp_path: Path) -> None:
    result = _run_cli(["keyboard-layout"], env_extra=_keyboard_env(tmp_path))
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["layout"] == "us"
    assert payload["configured"] is False


def test_cli_set_updates_the_included_config_and_reloads(tmp_path: Path) -> None:
    env = _keyboard_env(tmp_path)
    log = tmp_path / "niri-reload.log"
    env["NIRI_RELOAD_LOG"] = str(log)
    config_dir = Path(env["XDG_CONFIG_HOME"]) / "niri"
    config_dir.mkdir(parents=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/10-input.kdl"\n', encoding="utf-8"
    )
    (config_dir / "config.d").mkdir()
    included = config_dir / "config.d" / "10-input.kdl"
    included.write_text(
        "input {\n    keyboard {\n        xkb {\n"
        '            layout "us"\n'
        '            options "ctrl:nocaps"\n'
        "        }\n    }\n}\n",
        encoding="utf-8",
    )
    result = _run_cli(
        ["keyboard-layout", "--set", "latam"],
        env_extra=env,
        fake_bin={"niri": FAKE_NIRI_RELOAD},
    )
    assert result.returncode == 0, result.stderr
    written = included.read_text(encoding="utf-8")
    assert 'layout "latam"' in written
    assert 'options "ctrl:nocaps"' in written
    assert "msg action load-config-file" in log.read_text(encoding="utf-8")


def test_cli_set_accepts_a_variant(tmp_path: Path) -> None:
    env = _keyboard_env(tmp_path)
    env["NIRI_RELOAD_LOG"] = str(tmp_path / "niri-reload.log")
    result = _run_cli(
        ["keyboard-layout", "--set", "us", "intl"],
        env_extra=env,
        fake_bin={"niri": FAKE_NIRI_RELOAD},
    )
    assert result.returncode == 0, result.stderr
    written = (Path(env["XDG_CONFIG_HOME"]) / "niri" / "config.kdl").read_text(
        encoding="utf-8"
    )
    assert 'variant "intl"' in written


def test_apply_reports_reload_failure_after_writing(tmp_path: Path) -> None:
    env = _keyboard_env(tmp_path)
    log = tmp_path / "niri-reload.log"
    env["NIRI_RELOAD_LOG"] = str(log)
    config = Path(env["XDG_CONFIG_HOME"]) / "niri" / "config.kdl"
    config.parent.mkdir(parents=True)
    config.write_text("", encoding="utf-8")
    result = _run_cli(
        ["keyboard-layout", "--set", "es"],
        env_extra=env,
        fake_bin={"niri": FAKE_NIRI_RELOAD_FAIL},
    )
    assert result.returncode == 1
    assert "no se pudo recargar niri" in result.stderr
    assert 'layout "es"' in config.read_text(encoding="utf-8")


def test_cli_set_rejects_an_unknown_combination(tmp_path: Path) -> None:
    env = _keyboard_env(tmp_path)
    result = _run_cli(["keyboard-layout", "--set", "es", "latam"], env_extra=env)
    assert result.returncode == 1
    assert "es" in result.stderr
    assert "latam" in result.stderr


def test_usage_lists_keyboard_layout() -> None:
    result = _run_cli([])
    assert "keyboard-layout" in result.stderr
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tests/test_keyboard_layout_cli.py -v`

Expected: FAIL with missing functions and `comando desconocido: keyboard-layout`.

- [ ] **Step 3: Implement read/write/apply/main wiring**

Implementa los nombres de la Interfaces block. `read_niri_keyboard_layout` ignora lículas que empiezan con `//` y reconoce el bloque `xkb {}`; `read_keyboard_layout_file` usa `_kdl_lines_in_load_order` y deja ganar al último valor. `set_niri_keyboard_layout` conserva líneas ajenas y elimina `variant` cuando el argumento es `""`. `write_keyboard_layout` usa `.tmp` + `chmod 0o644` + `os.replace`.

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tests/test_keyboard_layout_cli.py -v`

Expected: PASS.

- [ ] **Step 5: No commit**

No ejecutar `git commit`.

### Task 3: Panel de teclado

**Files:**
- Create: `modules/secondmenu/KeyboardLayoutPanel.qml`
- Test: `tests/test_keyboard_layout_panel.py`

**Interfaces:**
- Consumes: Task 2 JSON de `caparazon-wm keyboard-layout`.
- Produces:
  - `KeyboardLayoutPanel.qml` con `Process` de carga y aplicación.
  - Funciones QML `applyState(payload)`, `currentLanguageOptions()`, `currentLanguageLabel()`, `chooseLanguage(index)`, `chooseVariant(index)`, `hasPendingChange()` y `applyKeyboard()`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_keyboard_layout_panel.py`:

```python
def test_keyboard_panel_reads_and_applies_through_the_cli() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"keyboard-layout"' in contents
    assert '"--set"' in contents
    assert "root.pendingLayout" in contents
    assert "root.pendingVariant" in contents


def test_keyboard_panel_does_not_talk_to_the_system() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert ".config/niri" not in contents
    assert "niri msg" not in contents
    assert "FileView" not in contents
    assert "QtQuick.Controls" not in contents


def test_keyboard_panel_groups_languages_and_variants() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "Grid {" in contents
    assert "Repeater {" in contents
    assert "SegmentedChoice" in contents
    assert "currentLanguageOptions()" in contents
    assert "chooseLanguage(modelData" in contents or "chooseLanguage(index)" in contents
    assert "chooseVariant(key)" in contents


def test_keyboard_panel_applies_the_variant_only_when_present() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index("function applyKeyboard()")
    end = contents.index("Process {", start)
    block = contents[start:end]
    assert "root.pendingVariant.length > 0" in block
    assert "root.pendingLayout" in block
    assert "root.pendingVariant" in block


def test_keyboard_panel_has_no_nested_scroll() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "Flickable" not in contents
    assert "GridView" not in contents
    assert "implicitHeight: content.implicitHeight + 12" in contents
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tests/test_keyboard_layout_panel.py -v`

Expected: FAIL because the panel does not exist.

- [ ] **Step 3: Implement the panel**

Implementa `KeyboardLayoutPanel.qml` siguiendo `CursorThemePanel.qml`: un `Process` de carga, otro de aplicación, estado JSON, chips de idioma en `Grid + Repeater`, variaciones con `SegmentedChoice`, botón **Aplicar** y texto de estado. El command de apply debe construirse con el array de tres elementos o con `root.pendingVariant` como cuarto elemento.

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tests/test_keyboard_layout_panel.py -v`

Expected: PASS.

- [ ] **Step 5: No commit**

No ejecutar `git commit`.

### Task 4: Reorden de Niri configs

**Files:**
- Modify: `modules/secondmenu/NiriConfigsPanel.qml`
- Test: `tests/test_niri_configs_panel.py`

**Interfaces:**
- Consumes: Task 3 `KeyboardLayoutPanel`.
- Produces: Orden final `monitorsHost` → `keyboardHost` → `panelHost`; `keyboardComponent`.

- [ ] **Step 1: Write the failing tests**

Actualiza `tests/test_niri_configs_panel.py`:

```python
def test_the_panel_orders_monitors_keyboard_and_themes() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "id: monitorsHost" in contents
    assert "id: keyboardHost" in contents
    assert "id: panelHost" in contents
    assert contents.index("id: monitorsHost") < contents.index("id: keyboardHost")
    assert contents.index("id: keyboardHost") < contents.index("id: panelHost")
```

Agrega:

```python
def test_the_panel_mounts_the_keyboard_panel() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "KeyboardLayoutPanel" in contents
    assert "id: keyboardComponent" in contents
    assert "sourceComponent: keyboardComponent" in contents
```

Cambia la aserción vieja de orden invirtiéndola: `contents.index("id: monitorsHost") < contents.index("id: panelHost")`.

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tests/test_niri_configs_panel.py -v`

Expected: FAIL en las nuevas aserciones de orden y teclado.

- [ ] **Step 3: Implement the reorder**

Reordena el `Column body`: cabecera, Monitores + `monitorsHost`, separador, Teclado + `keyboardHost`, separador, `Sección` + `SegmentedChoice` + `panelHost`. Agrega `keyboardComponent` con `KeyboardLayoutPanel` y su loader con altura desde `keyboardLoader.item.implicitHeight`.

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tests/test_niri_configs_panel.py -v`

Expected: PASS.

- [ ] **Step 5: No commit**

No ejecutar `git commit`.

### Task 5: Resoluciones plegables

**Files:**
- Modify: `modules/secondmenu/MonitorsPanel.qml`
- Test: `tests/test_monitors_panel.py`

**Interfaces:**
- Consumes: Estado actual de monitores y modos.
- Produces: `resolutionsOpen`, `selectedModeLabel()` y el trigger compacto.

- [ ] **Step 1: Write the failing tests**

Agrega a `tests/test_monitors_panel.py`:

```python
def test_resolutions_are_collapsed_by_default() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "property bool resolutionsOpen: false" in contents
    assert "function selectedModeLabel()" in contents
    assert "root.resolutionsOpen = !root.resolutionsOpen" in contents
    assert 'root.resolutionsOpen ? "▴" : "▾"' in contents
    assert "visible: root.resolutionsOpen" in contents


def test_resolutions_close_after_picking_a_mode() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index("model: root.selectedOutput() ? root.selectedOutput().modes : []")
    end = contents.index('text: "Rotación"', start)
    block = contents[start:end]
    assert "root.patchSelected({ mode: modelData.label })" in block
    assert "root.resolutionsOpen = false" in block


def test_monitors_panel_has_no_nested_scroll() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "Flickable" not in contents
    assert "GridView" not in contents
    assert "interactive" not in contents
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/pytest tests/test_monitors_panel.py -v`

Expected: FAIL en las nuevas aserciones.

- [ ] **Step 3: Implement the collapsible list**

Reemplaza el texto y `Column` de resoluciones por: etiqueta, rectángulo disparador con `selectedModeLabel()` y caret, `MouseArea` que alterna estado, y `Column` con `visible`/`height` ligados a `root.resolutionsOpen`. El `Repeater` existente se mueve dentro sin cambiar la lógica de selección; al elegir modo, cierra la lista.

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv/bin/pytest tests/test_monitors_panel.py -v`

Expected: PASS.

- [ ] **Step 5: No commit**

No ejecutar `git commit`.

### Task 6: Verificación nativa

**Files:**
- Modify: `~/.local/bin/caparazon-wm` si es copia, no si es symlink.
- Test: comandos de verificación.

- [ ] **Step 1: Run focused tests**

Run: `.venv/bin/pytest tests/test_keyboard_layout_cli.py tests/test_keyboard_layout_panel.py tests/test_niri_configs_panel.py tests/test_monitors_panel.py -v`

Expected: PASS.

- [ ] **Step 2: Run the full suite**

Run: `.venv/bin/pytest -q`

Expected: PASS con los skips preexistentes conocidos.

- [ ] **Step 3: Run static checks**

Run:

```bash
.venv/bin/python -m py_compile integration/bin/caparazon-wm.py
.venv/bin/ruff check integration/bin/caparazon-wm.py tests/test_keyboard_layout_cli.py tests/test_keyboard_layout_panel.py tests/test_niri_configs_panel.py tests/test_monitors_panel.py
/usr/lib/qt6/bin/qmllint modules/secondmenu/KeyboardLayoutPanel.qml modules/secondmenu/MonitorsPanel.qml modules/secondmenu/NiriConfigsPanel.qml
git diff --check
```

Expected: todo PASS; `qmllint` puede conservar warnings preexistentes pero `errors=0`.

- [ ] **Step 4: Check live CLI state without applying a layout**

Run: `~/.local/bin/caparazon-wm keyboard-layout`

Expected: JSON con `layout` igual al config real y `configured: true`.

- [ ] **Step 5: No commit**

No ejecutar `git commit`.

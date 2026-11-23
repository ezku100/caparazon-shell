# Niri Configs Cursor Implementation Plan

> **Para ejecutores:** sub-skill obligatoria: usar `superpowers:executing-plans` de forma nativa, tarea por tarea. No delegar a agentes premium. Cada paso usa checkbox (`- [ ]`).

**Goal:** Renombrar la categoría niri del submenú a `Niri configs`, agregar pestañas `Iconos`/`Cursor`, y hacer que elegir un tema Xcursor escriba el include de niri y recargue la configuración sin tocar KDE.

**Architecture:** `caparazon-wm` sigue siendo la única puerta al sistema: expone `cursor-theme` para detectar temas, leer el valor efectivo del árbol de includes de niri, escribir `xcursor-theme` en el fichero dueño y recargar niri. El wrapper QML `NiriConfigsPanel.qml` reparte entre el panel de iconos existente y un `CursorThemePanel.qml` nuevo; ambos paneles sólo llaman al CLI.

**Tech Stack:** Python 3 (CLI), pytest, ruff, QML/Quickshell, qmllint, KDL de niri.

**Spec:** `docs/superpowers/specs/2026-11-22-niri-configs-cursor-design.md`

## Global Constraints

- `"recuerda que no debemos afectar el funcionamiento de la shell con kde"`
- `"español"`
- `"TDD estricto"`
- `"sin commits sin petición explícita"`
- `"CLI como única puerta al sistema"`
- `"no delegar agentes premium"`
- "No se va a tocar `~/.config/autostart/caparazon.desktop` ni variables de entorno de KDE: el cambio es sólo config de niri."
- "No reiniciar Quickshell: el cursor se aplica con recarga de niri." (salvo recarga de verificación del propio shell tras instalar el CLI, que no cambia Preferences de KDE)

## Review Focus

- Include ownership: si `xcursor-theme` vive en `config.d/10-input-and-cursor.kdl`, `--set` debe escribir ahí y no en `config.kdl`; cubierto en Task 2, test `test_cursor_theme_set_writes_the_included_config_and_keeps_neighbors`.
- Neighbor preservation: `xcursor-size` y `hide-when-typing` deben sobrevivir; cubierto en Task 2, test `test_cursor_theme_set_writes_the_included_config_and_keeps_neighbors`.
- Reload failure: si `niri msg action load-config-file` falla, el CLI debe devolver código 1 con mensaje; cubierto en Task 2, test `test_cursor_theme_set_reports_reload_failure`.
- Unknown cursor: un nombre no instalado no debe crear ni modificar ficheros; cubierto en Task 2, test `test_cursor_theme_set_rejects_unknown_theme`.
- KDE isolation: la categoría sólo existe con `CompositorService.niri` y el panel no escribe config; cubierto en Task 3 y Task 5.

---

## File Structure

- Modify `integration/bin/caparazon-wm.py`: nuevo bloque `cursor-theme`, estado JSON, escritura KDL y recarga de niri.
- Modify `tests/test_caparazon_wm.py`: contratos del CLI `cursor-theme`.
- Create `modules/secondmenu/CursorThemePanel.qml`: selector de temas Xcursor.
- Create `tests/test_cursor_theme_niri.py`: contrato QML del panel de cursor.
- Create `modules/secondmenu/NiriConfigsPanel.qml`: wrapper con pestañas `Iconos`/`Cursor`.
- Create `tests/test_niri_configs_panel.py`: contrato QML del wrapper.
- Modify `modules/secondmenu/SecondMenu.qml`: categoría `niri-configs` y montaje de `NiriConfigsPanel`.
- Modify `tests/test_icon_theme_niri.py`: contratos actualizados de la categoría renombrada.
- Runtime artifact (no commit): `~/.local/bin/caparazon-wm` se sincroniza con el CLI del repo.

---

## Task 1: CLI — detectar y leer el tema de cursor

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_caparazon_wm.py`

**Interfaces:**
- Consumes: `niri_config_path()`, `_kdl_lines_in_load_order()`, `run()` del propio CLI.
- Produces: `CursorThemeState`, `cursor_theme_dirs()`, `installed_cursor_themes()`, `read_niri_cursor_theme(text: str) -> str`, `read_cursor_theme_file(path: Path) -> str`, `cursor_theme_state() -> CursorThemeState`, dispatch sin args de `cursor-theme` en `main()`.

- [ ] **Step 1: Write the failing helpers and state tests**

Append to `tests/test_caparazon_wm.py`:

```python
def _cursor_theme_env(tmp_path: Path) -> dict[str, str]:
    """Entorno aislado: HOME propio y rutas de datos propias."""
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    return {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_DIRS": str(tmp_path / "share"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
    }


def _write_cursor_theme(root: Path, name: str) -> None:
    """Crea un tema Xcursor mínimo: directorio cursors con un archivo."""
    cursors = root / name / "cursors"
    cursors.mkdir(parents=True, exist_ok=True)
    (cursors / "left_ptr").write_text("", encoding="utf-8")


def test_cursor_theme_lists_the_installed_themes(tmp_path: Path) -> None:
    _write_cursor_theme(tmp_path / "share" / "icons", "Oxygen_Black")
    _write_cursor_theme(tmp_path / "home" / ".local" / "share" / "icons", "MiCursor")

    result = _run_cli(["cursor-theme"], env_extra=_cursor_theme_env(tmp_path))

    assert result.returncode == 0, result.stderr
    themes = json.loads(result.stdout)["themes"]
    assert "Oxygen_Black" in themes
    assert "MiCursor" in themes


def test_cursor_theme_reports_the_default_without_a_config(tmp_path: Path) -> None:
    result = _run_cli(["cursor-theme"], env_extra=_cursor_theme_env(tmp_path))

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["current"] == "breeze_cursors"
    assert payload["default"] == "breeze_cursors"
    assert payload["configured"] is False


def test_cursor_theme_reads_the_theme_from_an_included_config(tmp_path: Path) -> None:
    environ = _cursor_theme_env(tmp_path)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/10-input-and-cursor.kdl"\n',
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    (config_dir / "config.d" / "10-input-and-cursor.kdl").write_text(
        "cursor {\n"
        '    xcursor-theme "Oxygen_Black"\n'
        "    xcursor-size 24\n"
        "    hide-when-typing\n"
        "}\n",
        encoding="utf-8",
    )

    result = _run_cli(["cursor-theme"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["current"] == "Oxygen_Black"
    assert payload["configured"] is True


def test_cursor_theme_last_value_in_load_order_wins(tmp_path: Path) -> None:
    environ = _cursor_theme_env(tmp_path)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/10-input-and-cursor.kdl"\n'
        "cursor {\n"
        '    xcursor-theme "Adwaita"\n'
        "}\n",
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    (config_dir / "config.d" / "10-input-and-cursor.kdl").write_text(
        'cursor {\n    xcursor-theme "breeze_cursors"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(["cursor-theme"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["current"] == "Adwaita"


def test_usage_lists_cursor_theme() -> None:
    result = _run_cli([])

    assert "cursor-theme" in result.stderr
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest tests/test_caparazon_wm.py -q -k cursor_theme`

Expected: FAIL with `cursor-theme` unknown command / JSON parse errors.

- [ ] **Step 3: Implement state/detection in `integration/bin/caparazon-wm.py`**

Add a `# --- tema de cursor ---` block before `# --- main ---` with:
- `DEFAULT_CURSOR_THEME: Final[str] = "breeze_cursors"`.
- `_CURSOR_THEME_ENTRY = re.compile(r'xcursor-theme\s+(?:"([^"]*)"|([^\s;}]+))')`.
- `_cursor_theme_value(text: str) -> str` returning group 1 or group 2 of that regex.
- `@dataclass(frozen=True, slots=True) class CursorThemeState` with fields `current: str`, `themes: tuple[str, ...]`, `default: str`, `configured: bool` and `to_json()` emitting exactly those keys.
- `cursor_theme_dirs() -> list[Path]`: `<XDG_DATA_DIRS>/icons`, `<XDG_DATA_HOME>/icons`, `~/.icons`, `~/.cursors`, con los mismos defaults que `icon_theme_dirs()`.
- `installed_cursor_themes() -> list[str]`: nombres ordenados y únicos donde `<raíz>/<nombre>/cursors` sea directorio.
- `read_niri_cursor_theme(text: str) -> str`: escaneo depth-aware del bloque `cursor {}`; devuelve el último `xcursor-theme` dentro del bloque.
- `read_cursor_theme_file(path: Path) -> str`: usa `_kdl_lines_in_load_order()` y asigna `value` cada vez que aparece un `xcursor-theme` dentro de un bloque `cursor`; devuelve el último valor.
- `cursor_theme_state() -> CursorThemeState`: `configured = read_cursor_theme_file(niri_config_path())`, `themes = tuple(installed_cursor_themes())`, `current = configured or DEFAULT_CURSOR_THEME`.
- Actualiza el docstring del módulo y la cadena de usage de `main()` para incluir `cursor-theme`.
- Agrega la rama `cursor-theme` en `main()`, antes de `logout`: sin `rest` → `print(cursor_theme_state().to_json())` y `0`; con cualquier opción → usage y `2`.

No agregues `--set` todavía; esa parte es de Task 2.

- [ ] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/pytest tests/test_caparazon_wm.py -q -k cursor_theme`

Expected: PASS.

---

## Task 2: CLI — escribir, recargar y despachar `cursor-theme --set`

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_caparazon_wm.py`

**Interfaces:**
- Consumes: `installed_cursor_themes()`, `read_cursor_theme_file()`, `niri_config_path()`, `_kdl_lines_in_load_order()`, `run()`.
- Produces: `set_niri_cursor_theme(text: str, name: str) -> str`, `_find_cursor_theme_file(path: Path) -> Path | None`, `write_cursor_theme(name: str) -> Path`, `reload_niri_config() -> int`, `cursor_theme_apply(name: str) -> int`, extensión `--set` del dispatch `cursor-theme` ya creado en Task 1.

- [ ] **Step 1: Write the failing apply tests**

Append to `tests/test_caparazon_wm.py`:

```python
FAKE_NIRI_RELOAD = """#!/bin/sh
printf '%s\\n' "$*" >> "$NIRI_RELOAD_LOG"
case "$*" in
  *load-config-file*) exit 0 ;;
  *) exit 1 ;;
esac
"""

FAKE_NIRI_RELOAD_FAIL = """#!/bin/sh
printf '%s\\n' "$*" >> "$NIRI_RELOAD_LOG"
case "$*" in
  *load-config-file*) exit 1 ;;
  *) exit 1 ;;
esac
"""


def test_cursor_theme_set_writes_the_included_config_and_keeps_neighbors(
    tmp_path: Path,
) -> None:
    _write_cursor_theme(tmp_path / "share" / "icons", "Oxygen_Black")
    environ = _cursor_theme_env(tmp_path)
    reload_log = tmp_path / "niri-reload.log"
    environ["NIRI_RELOAD_LOG"] = str(reload_log)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    config = config_dir / "config.kdl"
    config.write_text(
        'include "config.d/10-input-and-cursor.kdl"\n',
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    included = config_dir / "config.d" / "10-input-and-cursor.kdl"
    included.write_text(
        "cursor {\n"
        '    xcursor-theme "breeze_cursors"\n'
        "    xcursor-size 24\n"
        "    hide-when-typing\n"
        "}\n",
        encoding="utf-8",
    )

    result = _run_cli(
        ["cursor-theme", "--set", "Oxygen_Black"],
        env_extra=environ,
        fake_bin={"niri": FAKE_NIRI_RELOAD},
    )

    assert result.returncode == 0, result.stderr
    written = included.read_text(encoding="utf-8")
    assert 'xcursor-theme "Oxygen_Black"' in written
    assert "xcursor-size 24" in written
    assert "hide-when-typing" in written
    assert "xcursor-theme" not in config.read_text(encoding="utf-8")
    assert "msg action load-config-file" in reload_log.read_text(encoding="utf-8")
    check = _run_cli(["cursor-theme"], env_extra=environ)
    assert json.loads(check.stdout)["current"] == "Oxygen_Black"


def test_cursor_theme_set_creates_the_cursor_block_when_missing(tmp_path: Path) -> None:
    _write_cursor_theme(tmp_path / "share" / "icons", "Oxygen_Black")
    environ = _cursor_theme_env(tmp_path)
    environ["NIRI_RELOAD_LOG"] = str(tmp_path / "niri-reload.log")
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    config = config_dir / "config.kdl"
    config.write_text("input {\n    warp-pointer-to-focused-window\n}\n", encoding="utf-8")

    result = _run_cli(
        ["cursor-theme", "--set", "Oxygen_Black"],
        env_extra=environ,
        fake_bin={"niri": FAKE_NIRI_RELOAD},
    )

    assert result.returncode == 0, result.stderr
    written = config.read_text(encoding="utf-8")
    assert "cursor {" in written
    assert 'xcursor-theme "Oxygen_Black"' in written
    assert "warp-pointer-to-focused-window" in written


def test_cursor_theme_set_reports_reload_failure(tmp_path: Path) -> None:
    _write_cursor_theme(tmp_path / "share" / "icons", "Oxygen_Black")
    environ = _cursor_theme_env(tmp_path)
    reload_log = tmp_path / "niri-reload.log"
    environ["NIRI_RELOAD_LOG"] = str(reload_log)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    config = config_dir / "config.kdl"
    config.write_text(
        'cursor {\n    xcursor-theme "breeze_cursors"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(
        ["cursor-theme", "--set", "Oxygen_Black"],
        env_extra=environ,
        fake_bin={"niri": FAKE_NIRI_RELOAD_FAIL},
    )

    assert result.returncode == 1
    assert "no se pudo recargar niri" in result.stderr
    assert 'xcursor-theme "Oxygen_Black"' in config.read_text(encoding="utf-8")
    assert "msg action load-config-file" in reload_log.read_text(encoding="utf-8")


def test_cursor_theme_set_rejects_unknown_theme(tmp_path: Path) -> None:
    environ = _cursor_theme_env(tmp_path)

    result = _run_cli(["cursor-theme", "--set", "NoExiste"], env_extra=environ)

    assert result.returncode == 1
    assert "NoExiste" in result.stderr
    assert not (tmp_path / "home" / ".config" / "niri" / "config.kdl").exists()


def test_cursor_theme_set_needs_a_theme(tmp_path: Path) -> None:
    result = _run_cli(["cursor-theme", "--set"], env_extra=_cursor_theme_env(tmp_path))

    assert result.returncode == 2
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest tests/test_caparazon_wm.py -q -k cursor_theme`

Expected: FAIL because `--set` is not dispatched.

- [ ] **Step 3: Implement write/reload/apply and main wiring**

In `integration/bin/caparazon-wm.py`:
- `set_niri_cursor_theme(text: str, name: str) -> str`: localiza el primer bloque `cursor {}` con escaneo depth-aware; reemplaza cada línea `xcursor-theme` por `    xcursor-theme "<name>"`; si no hay entrada, la agrega; si no hay bloque, agrega al final:

  ```kdl
  cursor {
      xcursor-theme "<name>"
  }
  ```

  Conserva todas las demás líneas y termina con `\n`.
- `_find_cursor_theme_file(path: Path) -> Path | None`: igual que `_find_icon_theme_file()` pero dentro de bloques `cursor`; devuelve el último fichero que aporta `xcursor-theme`.
- `write_cursor_theme(name: str) -> Path`: `target = _find_cursor_theme_file(root) or root`; lectura tolerante, atomic write vía `.tmp`, `chmod 0o644`, `os.replace`.
- `reload_niri_config() -> int`: `niri = shutil.which("niri")`; si falta, devuelve 1; si no, devuelve `run([niri, "msg", "action", "load-config-file"]).returncode`.
- `cursor_theme_apply(name: str) -> int`: valida contra `installed_cursor_themes()`; tema desconocido → `cursor-theme: tema desconocido: <name>` en stderr y código 1; si no, `write_cursor_theme(name)` y `reload_niri_config()`; si la recarga falla, escribe `cursor-theme: no se pudo recargar niri` en stderr y devuelve 1.
- Extiende el dispatch `cursor-theme` ya creado en Task 1: con `--set` y valor → `cursor_theme_apply(...)`; con `--set` sin valor → usage y código 2; con otra opción → usage y código 2. La rama sin args no cambia.

- [ ] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/pytest tests/test_caparazon_wm.py -q`

Expected: PASS.

---

## Task 3: QML — panel de tema de cursor

**Files:**
- Create: `modules/secondmenu/CursorThemePanel.qml`
- Test: `tests/test_cursor_theme_niri.py`

**Interfaces:**
- Consumes: CLI `caparazon-wm cursor-theme` y `cursor-theme --set <tema>` de Task 1-2.
- Produces: `CursorThemePanel` con `themes`, `current`, `defaultTheme`, `pendingTheme`, `errorMessage`, `noticeMessage`, `applying`, `applyState(payload)`, `choose(theme)`.

- [ ] **Step 1: Write the failing cursor panel tests**

Create `tests/test_cursor_theme_niri.py`:

```python
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "CursorThemePanel.qml"


def test_the_cursor_panel_reads_and_writes_through_the_cli() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert '"caparazon-wm"' in contents
    assert '"cursor-theme"' in contents
    assert '"--set"' in contents


def test_the_cursor_panel_does_not_write_configuration_files() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert ".config/niri" not in contents
    assert "FileView" not in contents


def test_the_cursor_panel_does_not_announce_a_restart() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "reinici" not in contents


def test_the_cursor_panel_shows_a_pointer_glyph_and_success_notice() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "↖" in contents
    assert "cell.active" in contents
    assert "Cursor aplicado." in contents
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest tests/test_cursor_theme_niri.py -q`

Expected: FAIL because the file does not exist.

- [ ] **Step 3: Create the cursor panel**

Create `modules/secondmenu/CursorThemePanel.qml`:
- Imports `Quickshell`, `Quickshell.Io`, `QtQuick`, `"../../theme"`.
- `Item` con propiedades `themes: []`, `current: ""`, `defaultTheme: ""`, `pendingTheme: ""`, `errorMessage: ""`, `noticeMessage: ""`, `applying: false`.
- `Component.onCompleted: load.running = true`.
- `applyState(payload)`: `JSON.parse`, asigna `data.themes`, `data.current`, `data.default`; error `No se pudo leer la lista de cursores`.
- `choose(theme)`: ignora tema actual o `applying`; limpia mensajes; fija `pendingTheme` y lanza `apply`.
- `Process { id: load; command: ["caparazon-wm", "cursor-theme"]; stdout: StdioCollector { onStreamFinished: root.applyState(text) } }`.
- `Process { id: apply; command: ["caparazon-wm", "cursor-theme", "--set", root.pendingTheme]; stderr: StdioCollector { onStreamFinished: root.errorMessage = String(text || "").trim() }; onExited: actualiza `applying`, `current`, `noticeMessage = "Cursor aplicado."` o error por defecto `No se pudo aplicar el cursor` }`.
- UI: `Text` título `Tema del cursor`, subtítulo `El aspecto del puntero en la sesión niri.`, `GridView` con `cellHeight: 104`, delegate con `id: cell`, `property bool active: root.current === cell.modelData`, `Text { text: "↖" }`, nombre del tema resaltando `cell.active`, `MouseArea.onClicked: root.choose(cell.modelData)` y `footer` con error/notice. Usa los mismos tokens `Theme.*` que `IconThemePanel.qml`.
- Sin rutas de config, sin `FileView`, sin texto `reinici`.

- [ ] **Step 4: Run tests and QML lint**

Run:
```bash
.venv/bin/pytest tests/test_cursor_theme_niri.py -q
qmllint modules/secondmenu/CursorThemePanel.qml
```

Expected: PASS; `qmllint` without errors (warnings allowed).

---

## Task 4: QML — wrapper de pestañas `Iconos`/`Cursor`

**Files:**
- Create: `modules/secondmenu/NiriConfigsPanel.qml`
- Test: `tests/test_niri_configs_panel.py`

**Interfaces:**
- Consumes: `IconThemePanel.qml`, `CursorThemePanel.qml` (creado en Task 3).
- Produces: `NiriConfigsPanel` con `property string tab: "iconos"` y `Loader` que monta un panel u otro.

- [ ] **Step 1: Write the failing wrapper tests**

Create `tests/test_niri_configs_panel.py`:

```python
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "NiriConfigsPanel.qml"


def test_the_wrapper_defaults_to_the_icon_tab() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert 'property string tab: "iconos"' in contents
    assert 'label: "Iconos"' in contents
    assert 'label: "Cursor"' in contents


def test_the_wrapper_mounts_both_panels() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "IconThemePanel" in contents
    assert "CursorThemePanel" in contents
    assert 'root.tab === "iconos"' in contents


def test_the_wrapper_does_not_talk_to_the_system() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "Process" not in contents
    assert "caparazon-wm" not in contents
    assert ".config/niri" not in contents
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest tests/test_niri_configs_panel.py -q`

Expected: FAIL because the file does not exist.

- [ ] **Step 3: Create the wrapper**

Create `modules/secondmenu/NiriConfigsPanel.qml`:
- `import QtQuick`, `import "../../theme"`.
- `Item { id: root; property string tab: "iconos" }`.
- `Column` con `Row` de dos pestañas (`Iconos`, `Cursor`) usando `Rectangle`, `Text`, `MouseArea` y tokens `Theme.*` existentes (`m3SurfaceContainerHigh`, `m3OutlineVariant`, `textDim`, `fontUI`, `radius`). Cada pestaña expone `label: "Iconos"` o `label: "Cursor"`.
- `Loader` con `anchors.fill: parent`, `sourceComponent: root.tab === "iconos" ? iconComponent : cursorComponent`.
- `Component { id: iconComponent; IconThemePanel { anchors.fill: parent } }`.
- `Component { id: cursorComponent; CursorThemePanel { anchors.fill: parent } }`.
- Sin `Process`, sin `caparazon-wm`, sin rutas de configuración.

- [ ] **Step 4: Run tests and QML lint**

Run:
```bash
.venv/bin/pytest tests/test_niri_configs_panel.py -q
qmllint modules/secondmenu/NiriConfigsPanel.qml
```

Expected: PASS; `qmllint` without errors (warnings allowed).

---

## Task 5: QML — renombrar la categoría a `Niri configs`

**Files:**
- Modify: `modules/secondmenu/SecondMenu.qml`
- Test: `tests/test_icon_theme_niri.py`

**Interfaces:**
- Consumes: `CompositorService.niri`, `NiriConfigsPanel.qml` (creado en Task 4).
- Produces: categoría `key: "niri-configs"`, `label: "Niri configs"`, montaje desde `root.category === "niri-configs"`.

- [ ] **Step 1: Write the failing category tests**

Replace in `tests/test_icon_theme_niri.py` these two tests:

```python
def test_the_icon_category_only_shows_on_niri() -> None:
    contents = SECOND_MENU.read_text(encoding="utf-8")

    assert "CompositorService.niri" in contents
    assert '"niri-configs"' in contents
    assert '"Niri configs"' in contents
    assert '"iconos"' not in contents


def test_the_niri_configs_category_mounts_the_tabs_panel() -> None:
    contents = SECOND_MENU.read_text(encoding="utf-8")

    assert "NiriConfigsPanel" in contents
    assert 'root.category === "niri-configs"' in contents
```

Also update the module docstring line `para ofrecer la categoría "Iconos"` → `para ofrecer la categoría "Niri configs"`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest tests/test_icon_theme_niri.py -q -k 'niri_configs or icon_category'`

Expected: FAIL because `SecondMenu.qml` still uses `iconos`/`IconThemePanel`.

- [ ] **Step 3: Rename the category and its loader in `modules/secondmenu/SecondMenu.qml`**

- `iconCategory` → `niriConfigsCategory`.
- `key: "iconos"` → `key: "niri-configs"`.
- `label: "Iconos"` → `label: "Niri configs"`.
- `categories`: `[root.niriConfigsCategory]`.
- `sourceComponent`: `if (root.category === "niri-configs") return niriConfigsComponent;`.
- Component `id: iconComponent` → `id: niriConfigsComponent`.
- Inside it mount `NiriConfigsPanel { anchors.fill: parent }`.
- Actualiza el comentario de la línea 73 para hablar de ajustes de niri, no sólo iconos.

- [ ] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/pytest tests/test_icon_theme_niri.py -q`

Expected: PASS.

---

## Task 6: Verificación completa y change en vivo

**Files:**
- Runtime: `~/.local/bin/caparazon-wm`
- No repository files beyond previous tasks.

**Interfaces:**
- Consumes: todos los cambios anteriores.
- Produces: suite verde, CLI instalada, shell recargada, config de niri verificada y restaurada.

- [ ] **Step 1: Run full automated checks**

Run:
```bash
.venv/bin/pytest -q --tb=line
.venv/bin/ruff check --output-format concise .
git diff --check
qmllint modules/secondmenu/SecondMenu.qml modules/secondmenu/IconThemePanel.qml modules/secondmenu/NiriConfigsPanel.qml modules/secondmenu/CursorThemePanel.qml
```

Expected:
- pytest: PASS (baseline 1 skipped).
- ruff: sin errores nuevos en archivos tocados; los 29 errores baseline preexistentes pueden seguir.
- `git diff --check`: sin salida.
- `qmllint`: sin errores; warnings `unqualified` preexistentes aceptados.

- [ ] **Step 2: Install CLI used by the shell**

Run: `install -m 755 integration/bin/caparazon-wm.py "$HOME/.local/bin/caparazon-wm"`

Verify: `caparazon-wm cursor-theme` imprime JSON con `current: "breeze_cursors"` y la lista de temas detectados.

Expected: exit 0 y JSON válido.

- [ ] **Step 3: Reload the shell for QML changes**

Run:
```bash
pkill -TERM -f '^quickshell -p /home/ezku/Projects/caparazon-shell -d$'
sleep 1
setsid env MALLOC_ARENA_MAX=2 MALLOC_TRIM_THRESHOLD_=131072 mesa_glthread=false QS_ICON_THEME=Tela-dark CAPARAZON_ICON_THEME=Tela-dark quickshell -p /home/ezku/Projects/caparazon-shell -d >/tmp/ezku/caparazon-shell.log 2>&1 &
```

Verify: `pgrep -af 'quickshell -p /home/ezku/Projects/caparazon-shell -d'` shows exactly one process; `loginctl` session remains active.

Expected: shell up; no Plasma/KWin config touched.

- [ ] **Step 4: Verify live CLI-to-niri path and restore preference**

Run:
```bash
grep -n 'xcursor-theme' ~/.config/niri/config.d/10-input-and-cursor.kdl
caparazon-wm cursor-theme --set Oxygen_Black
grep -n 'xcursor-theme' ~/.config/niri/config.d/10-input-and-cursor.kdl
caparazon-wm cursor-theme --set breeze_cursors
grep -n 'xcursor-theme' ~/.config/niri/config.d/10-input-and-cursor.kdl
```

Expected:
- Primera y última línea: `xcursor-theme "breeze_cursors"`.
- Intermedia: `xcursor-theme "Oxygen_Black"`.
- Ambos `--set` devuelven 0; `xcursor-size 24` y `hide-when-typing` siguen presentes.

- [ ] **Step 5: Visual QA**

Open the menu with `caparazon-shell-ipc menu2 open niri-configs` and invoke the `visual-qa` skill.

Expected: rail shows only one niri config category labelled `Niri configs`; panel shows tabs `Iconos` and `Cursor`; cursor tab lists installed themes and highlights `breeze_cursors`.

- [ ] **Step 6: Do not commit**

No repository commit. User constraint: `"sin commits sin petición explícita"`.

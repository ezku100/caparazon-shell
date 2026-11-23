# Niri Monitors Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar a **Niri configs** un panel de monitores que detecte salidas, edite modo/rotación/posición y principal, persista el cambio en el config de niri y lo refleje en `primary-output` para toda la shell.

**Architecture:** El CLI `caparazon-wm` es el único que habla con niri y escribe archivos: consulta `niri msg --json outputs`, valida el payload, escribe `config.d/15-outputs.kdl`, añade su `include` a `config.kdl`, recarga niri y enfoca el principal. El QML sólo llama al CLI y renderiza el estado; `ShellLayout.qml` sigue consumiendo `caparazon-wm primary-output`.

**Tech Stack:** Python 3 con stdlib en `integration/bin/caparazon-wm.py`; QML/QtQuick con Quickshell en `modules/secondmenu/`; pytest, qmllint, ruff; niri 26.04.

**Spec:** `docs/superpowers/specs/2026-11-22-niri-monitors-design.md`

## Global Constraints

- Español en mensajes, errores y texto visible.
- Sin commits salvo petición explícita.
- TDD estricto: tests primero, implementación después.
- Sin delegación a agentes premium; trabajo directo con el modelo actual.
- Ejecución nativa: pytest, qmllint y QA con niri real.
- El CLI es la única puerta al sistema.
- No se debe afectar el funcionamiento de la shell con KDE.
- No tocar `40-environment.kdl`, `50-startup.kdl`, `~/.config/autostart` ni archivos de KDE.
- No exponer `scale`, VRR, apagado de outputs ni modos personalizados.
- No disponer monitores automáticamente: los valores `x/y` son explícitos.
- No cambiar el comportamiento de `primary-output` en KDE/Plasma; el cambio es sólo para niri.
- No crear pestañas propias fuera de `SegmentedChoice` + `Loader`.
- No usar `QtQuick.Controls`.

## Review Focus

- Un monitor desconectado con bloque guardado: un apply no debe borrarlo — pinned en Task 3, `test_apply_preserves_disconnected_output_blocks`.
- Un bloque `output` activo fuera de `15-outputs.kdl`: debe fallar sin duplicarlo — pinned en Task 3, `test_apply_refuses_foreign_output_blocks`.
- Un `focus-at-startup` configurado para un monitor desconectado: `primary-output` debe caer al superior izquierdo — pinned en Task 4, `test_primary_output_ignores_configured_but_disconnected_monitor`.
- `refresh_rate` en milihz: el modo debe imprimirse con tres decimales exactos — pinned en Task 2, `test_mode_label_formats_millihertz`.
- QML escribiendo config o llamando a niri: debe estar prohibido por contrato — pinned en Task 6, `test_monitors_panel_does_not_talk_to_the_system`.
- Compositor KDE: `monitors` debe devolver error JSON sin tocar nada — pinned en Task 2, `test_monitor_state_reports_non_niri_compositor`.

---

### Task 1: Base KDL de outputs en el CLI

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_niri_monitors_cli.py`

**Interfaces:**
- Consumes: `niri_config_path()`, `_kdl_brace_delta()`, `_kdl_lines_in_load_order()` ya existentes.
- Produces:
  - `OutputBlock`: dataclass frozen/slots con `name: str`, `mode: str`, `scale: float`, `transform: str`, `x: int`, `y: int`, `primary: bool`, `vrr: bool`.
  - `output_config_path(root: Path) -> Path` → `root.parent / "config.d" / "15-outputs.kdl"`.
  - `strip_kdl_comments(text: str) -> str`.
  - `find_output_blocks(text: str) -> list[tuple[str, str]]`.
  - `read_output_configs(path: Path) -> dict[str, OutputBlock]`.
  - `configured_primary_output(outs: dict[str, Any]) -> str`.
  - `format_scale(value: float) -> str`.
  - `render_output_configs(blocks: dict[str, OutputBlock]) -> str`.
  - `ensure_outputs_include(root: Path) -> None`.
  - `write_output_configs(root: Path, blocks: dict[str, OutputBlock]) -> Path`.
  - `foreign_output_files(root: Path) -> list[Path]`.

- [x] **Step 1: Write the failing tests**

Create `tests/test_niri_monitors_cli.py` con el cargador del CLI, un helper de escritura y estos tests:

```python
from __future__ import annotations

import importlib.util
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLI = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-wm.py"


def _load_cli() -> ModuleType:
    spec = importlib.util.spec_from_file_location("caparazon_wm", CLI)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def test_find_output_blocks_ignores_commented_examples() -> None:
    cli = _load_cli()
    text = '// output "DP-1" {\n//     mode "1024x768@60.004"\n// }\n'
    assert cli.find_output_blocks(text) == []


def test_read_output_configs_parses_all_fields() -> None:
    cli = _load_cli()
    path = Path(tempfile.mkdtemp()) / "15-outputs.kdl"
    path.write_text(
        'output "HDMI-A-1" {\n'
        '    mode "1920x1080@60.000"\n'
        '    scale 1.5\n'
        '    transform "90"\n'
        '    position x=1024 y=0\n'
        '    focus-at-startup\n'
        '    variable-refresh-rate\n'
        '}\n',
        encoding="utf-8",
    )
    assert cli.read_output_configs(path) == {
        "HDMI-A-1": cli.OutputBlock(
            name="HDMI-A-1",
            mode="1920x1080@60.000",
            scale=1.5,
            transform="90",
            x=1024,
            y=0,
            primary=True,
            vrr=True,
        )
    }


def test_render_output_configs_emits_primary_and_vrr() -> None:
    cli = _load_cli()
    block = cli.OutputBlock(
        name="DP-1",
        mode="1024x768@60.004",
        scale=1,
        transform="normal",
        x=0,
        y=0,
        primary=True,
        vrr=False,
    )
    text = cli.render_output_configs({"DP-1": block})
    assert 'output "DP-1" {' in text
    assert 'mode "1024x768@60.004"' in text
    assert "scale 1" in text
    assert 'transform "normal"' in text
    assert "position x=0 y=0" in text
    assert "focus-at-startup" in text
    assert "variable-refresh-rate" not in text


def test_write_output_configs_adds_include_once() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    root.parent.mkdir(parents=True, exist_ok=True)
    root.write_text('include "config.d/10-input-and-cursor.kdl"\n', encoding="utf-8")
    block = cli.OutputBlock(
        name="HDMI-A-1",
        mode="1920x1080@60.000",
        scale=1,
        transform="normal",
        x=1024,
        y=0,
        primary=True,
        vrr=False,
    )
    target = cli.write_output_configs(root, {"HDMI-A-1": block})
    cli.write_output_configs(root, {"HDMI-A-1": block})
    assert target == root.parent / "config.d" / "15-outputs.kdl"
    assert root.read_text(encoding="utf-8").count('include "config.d/15-outputs.kdl"') == 1


def test_foreign_output_files_ignores_comments_and_own_file() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    config_d = root.parent / "config.d"
    config_d.mkdir(parents=True)
    root.write_text(
        'include "config.d/10-input-and-cursor.kdl"\n'
        'include "config.d/15-outputs.kdl"\n'
        'include "config.d/90-user-extra.kdl"\n',
        encoding="utf-8",
    )
    (config_d / "10-input-and-cursor.kdl").write_text(
        '// output "eDP-1" {\n//     mode "1920x1080@60.000"\n// }\n',
        encoding="utf-8",
    )
    own = config_d / "15-outputs.kdl"
    own.write_text('output "DP-1" {\n    mode "1024x768@60.004"\n}\n', encoding="utf-8")
    (config_d / "90-user-extra.kdl").write_text(
        'output "HDMI-A-1" {\n    mode "1920x1080@60.000"\n}\n',
        encoding="utf-8",
    )
    files = cli.foreign_output_files(root)
    assert files == [config_d / "90-user-extra.kdl"]


def test_configured_primary_output_uses_focus_at_startup() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    cli.write_output_configs(
        root,
        {
            "HDMI-A-1": cli.OutputBlock(
                name="HDMI-A-1",
                mode="1920x1080@60.000",
                scale=1,
                transform="normal",
                x=1024,
                y=0,
                primary=True,
                vrr=False,
            )
        },
    )
    os.environ["NIRI_CONFIG"] = str(root)
    try:
        outs = {"HDMI-A-1": {"current_mode": 0}, "DP-1": {"current_mode": 0}}
        assert cli.configured_primary_output(outs) == "HDMI-A-1"
    finally:
        os.environ.pop("NIRI_CONFIG", None)
```

- [x] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest -q tests/test_niri_monitors_cli.py`

Expected: FAIL con `AttributeError` para las funciones nuevas.

- [x] **Step 3: Implement the KDL foundation in `integration/bin/caparazon-wm.py`**

Agregar una sección `--- configuración de outputs ---`. Usar `re` y `json` ya importados. `strip_kdl_comments` debe respetar comillas dobles y `\"`. `find_output_blocks` debe usar regex `^\s*output\s+"([^"]+)"\s*\{` sobre líneas sin comentarios y `_kdl_brace_delta()` para cerrar el bloque. `read_output_configs` debe buscar `mode`, `scale`, `transform`, `position x=... y=...`, `focus-at-startup` y `variable-refresh-rate` dentro de cada bloque; valores por defecto: modo `""`, scale `1.0`, transform `"normal"`, posición `0,0`. `format_scale` debe devolver entero sin decimales cuando el valor sea entero. `ensure_outputs_include` debe insertar el include después de `include "config.d/10-input-and-cursor.kdl"`; si esa línea no existe, agregarlo al final. `write_output_configs` debe crear `config.d`, escribir el archivo vía `.tmp` + `chmod 0o644` + `os.replace`, y luego llamar a `ensure_outputs_include`. `foreign_output_files` debe agrupar `_kdl_lines_in_load_order(root)` por archivo, comparar rutas resueltas contra `output_config_path(root)`, y devolver los archivos ajenos con bloques activos.

- [x] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/pytest -q tests/test_niri_monitors_cli.py`

Expected: PASS.

---

### Task 2: Estado JSON de monitores

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_niri_monitors_cli.py`

**Interfaces:**
- Consumes: `run()`, `detect_compositor()`, `_niri_outputs_map()`, `_niri_output_enabled()`, `configured_primary_output()`, `output_config_path()`, `mode_label`, `normalize_transform`.
- Produces:
  - `mode_label(width: int, height: int, refresh_mhz: int) -> str`.
  - `normalize_transform(value: str) -> str`.
  - `_niri_output_position(info: Any) -> tuple[float, float]`.
  - `primary_output_niri_fallback(outs: dict[str, Any]) -> str`.
  - `MonitorOutputState` y `MonitorState`: dataclasses frozen/slots con `to_json()`.
  - `monitor_state() -> MonitorState`.
  - Subcomando `monitors` en `main()` y en el docstring/usage.

- [x] **Step 1: Write the failing tests**

Agregar al mismo archivo de tests:

```python
def _run_cli(
    args: list[str],
    *,
    env_extra: dict[str, str] | None = None,
    fake_bin: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.pop("NIRI_SOCKET", None)
    if env_extra:
        env.update(env_extra)
    if fake_bin:
        tmp = tempfile.mkdtemp(prefix="cwm-mon-")
        for name, body in fake_bin.items():
            _write_exec(Path(tmp) / name, body)
        env["PATH"] = tmp + os.pathsep + env.get("PATH", "")
    return subprocess.run(["python3", str(CLI), *args], capture_output=True, text=True, env=env, timeout=30, check=False)


FAKE_NIRI_OUTPUTS = """#!/bin/sh
case "$*" in
  *version*) echo "26.04"; exit 0 ;;
  *outputs*)
    cat <<'JSON'
{
  "HDMI-A-1": {
    "name": "HDMI-A-1", "make": "Xiaomi Corporation", "model": "P27FBA-RAGL",
    "serial": "5106500094111", "current_mode": 0, "vrr_enabled": false,
    "logical": {"x": 1024, "y": 0, "width": 1920, "height": 1080, "scale": 1.0, "transform": "Normal"},
    "modes": [
      {"width": 1920, "height": 1080, "refresh_rate": 60000, "is_preferred": true},
      {"width": 1280, "height": 720, "refresh_rate": 75000, "is_preferred": false}
    ]
  },
  "DP-1": {
    "name": "DP-1", "make": "Integrated Tech Express Inc", "model": "DP2VGA V235",
    "serial": "", "current_mode": 0, "vrr_enabled": false,
    "logical": {"x": 0, "y": 0, "width": 1024, "height": 768, "scale": 1.0, "transform": "Normal"},
    "modes": [{"width": 1024, "height": 768, "refresh_rate": 60004, "is_preferred": true}]
  }
}
JSON
    exit 0 ;;
  *) exit 1 ;;
esac
"""


def test_mode_label_formats_millihertz() -> None:
    cli = _load_cli()
    assert cli.mode_label(1920, 1080, 60000) == "1920x1080@60.000"
    assert cli.mode_label(1024, 768, 60004) == "1024x768@60.004"
    assert cli.mode_label(1280, 720, 59940) == "1280x720@59.940"


def test_monitor_state_reports_configured_primary_and_logical_position() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    cli.write_output_configs(
        root,
        {
            "HDMI-A-1": cli.OutputBlock(
                name="HDMI-A-1", mode="1920x1080@60.000", scale=1,
                transform="normal", x=1024, y=0, primary=True, vrr=False,
            )
        },
    )
    result = _run_cli(
        ["monitors"],
        env_extra={"NIRI_SOCKET": "/run/user/1000/niri.sock", "NIRI_CONFIG": str(root)},
        fake_bin={"niri": FAKE_NIRI_OUTPUTS},
    )
    assert result.returncode == 0, result.stderr
    state = json.loads(result.stdout)
    hdmi = next(item for item in state["outputs"] if item["name"] == "HDMI-A-1")
    assert hdmi["primary"] is True
    assert hdmi["primary_configured"] is True
    assert hdmi["transform"] == "normal"
    assert hdmi["x"] == 1024 and hdmi["y"] == 0
    assert hdmi["mode"] == "1920x1080@60.000"
    assert hdmi["modes"][0] == {"label": "1920x1080@60.000", "preferred": True, "current": True}
    assert state["configured"] is True
    assert state["error"] == ""


def test_monitor_state_reports_non_niri_compositor() -> None:
    result = _run_cli(
        ["monitors"],
        fake_bin={"busctl": '#!/bin/sh\necho \'s "DP-1"\'\n', "niri": "#!/bin/sh\nexit 1\n"},
    )
    assert result.returncode == 0, result.stderr
    state = json.loads(result.stdout)
    assert state["outputs"] == []
    assert "sólo niri" in state["error"]
```

Agregar `import json` a los imports del archivo de tests.

- [x] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest -q tests/test_niri_monitors_cli.py -k "mode_label or monitor_state"`

Expected: FAIL con `AttributeError` para `mode_label`/`monitor_state` o `Unknown command: monitors`.

- [x] **Step 3: Implement `monitor_state()` y el subcomando**

Agregar `mode_label` y `normalize_transform` antes de `monitor_state()`. Definir `MonitorOutputState` con campos `name, label, make, model, serial, primary, primary_configured, mode, modes, transform, x, y` y `MonitorState` con `outputs, configured, error`. `label` debe ser `f"{model} ({make})"` o `model` si no hay make. `modes` debe ser una lista de dicts `label/preferred/current` en el orden que entrega niri, sin deduplicar. `monitor_state()` debe:
1. Si `detect_compositor() != "niri"`, devolver `MonitorState((), False, "monitores: sólo niri")`.
2. Ejecutar `niri msg --json outputs` con `shutil.which("niri")`; si falla, devolver error.
3. Obtener `outs` con `_niri_outputs_map`.
4. Obtener `primary = configured_primary_output(outs) or primary_output_niri_fallback(outs)`. Extraer el fallback actual de `primary_output_niri()` a `primary_output_niri_fallback(outs)`, usando `_niri_output_position(info)`; no cambiar aún el comportamiento público de `primary_output_niri()`.
5. Leer posición desde `info["logical"]["x"|"y"]`, con fallback a `info["x"|"y"]`.
6. Leer transform desde `logical.transform` y normalizarlo a minúsculas.
7. Marcar `configured` si `output_config_path(niri_config_path()).is_file()`.
`to_json()` debe usar `json.dumps` con las claves exactas del spec. En `main()`, agregar `monitors` al usage/docstring y al dispatch: sin args imprime `monitor_state().to_json()` y devuelve `0`.

- [x] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/pytest -q tests/test_niri_monitors_cli.py`

Expected: PASS.

---

### Task 3: Aplicación validada de la configuración

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_niri_monitors_cli.py`

**Interfaces:**
- Consumes: `find_output_blocks`, `read_output_configs`, `write_output_configs`, `foreign_output_files`, `mode_label`, `normalize_transform`, `configured_primary_output`.
- Produces:
  - `build_monitor_blocks(payload: Any, outs: dict[str, Any], existing: dict[str, OutputBlock]) -> dict[str, OutputBlock]`.
  - `monitor_apply(payload_json: str) -> int`.
  - `monitors --apply <json>` en `main()`.

- [x] **Step 1: Write the failing tests**

Agregar a `tests/test_niri_monitors_cli.py`:

```python
FAKE_NIRI_APPLY = """#!/bin/sh
case "$*" in
  *version*) echo "26.04"; exit 0 ;;
  *outputs*)
    cat <<'JSON'
{
  "HDMI-A-1": {
    "name": "HDMI-A-1", "current_mode": 0, "vrr_enabled": false,
    "logical": {"x": 1024, "y": 0, "width": 1920, "height": 1080, "scale": 1.0, "transform": "Normal"},
    "modes": [{"width": 1920, "height": 1080, "refresh_rate": 60000, "is_preferred": true}]
  }
}
JSON
    exit 0 ;;
  *load-config-file*) echo "reload" >> "$NIRI_LOG"; exit 0 ;;
  *focus-monitor*) echo "focus:$3" >> "$NIRI_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
"""


def _apply_env(root: Path, log: Path) -> dict[str, str]:
    return {
        "NIRI_SOCKET": "/run/user/1000/niri.sock",
        "NIRI_CONFIG": str(root),
        "NIRI_LOG": str(log),
    }


def test_apply_writes_blocks_includes_reloads_and_focuses() -> None:
    cli = _load_cli()
    tmp = Path(tempfile.mkdtemp())
    root = tmp / "config.kdl"
    root.write_text('include "config.d/10-input-and-cursor.kdl"\n', encoding="utf-8")
    log = tmp / "niri.log"
    payload = {
        "primary": "HDMI-A-1",
        "outputs": [
            {"name": "HDMI-A-1", "mode": "1920x1080@60.000", "transform": "normal", "x": 1024, "y": 0}
        ],
    }
    result = _run_cli(
        ["monitors", "--apply", json.dumps(payload)],
        env_extra=_apply_env(root, log),
        fake_bin={"niri": FAKE_NIRI_APPLY},
    )
    assert result.returncode == 0, result.stderr
    text = cli.output_config_path(root).read_text(encoding="utf-8")
    assert 'output "HDMI-A-1" {' in text
    assert "focus-at-startup" in text
    assert root.read_text(encoding="utf-8").count('include "config.d/15-outputs.kdl"') == 1
    assert log.read_text(encoding="utf-8").splitlines() == ["reload", "focus:HDMI-A-1"]


def test_apply_rejects_unavailable_mode_without_writing() -> None:
    cli = _load_cli()
    tmp = Path(tempfile.mkdtemp())
    root = tmp / "config.kdl"
    root.write_text('include "config.d/10-input-and-cursor.kdl"\n', encoding="utf-8")
    payload = {
        "primary": "HDMI-A-1",
        "outputs": [
            {"name": "HDMI-A-1", "mode": "3840x2160@60.000", "transform": "normal", "x": 0, "y": 0}
        ],
    }
    result = _run_cli(
        ["monitors", "--apply", json.dumps(payload)],
        env_extra=_apply_env(root, tmp / "niri.log"),
        fake_bin={"niri": FAKE_NIRI_APPLY},
    )
    assert result.returncode == 1
    assert "modo no disponible" in result.stderr
    assert not cli.output_config_path(root).exists()


def test_apply_refuses_foreign_output_blocks() -> None:
    cli = _load_cli()
    tmp = Path(tempfile.mkdtemp())
    root = tmp / "config.kdl"
    config_d = tmp / "config.d"
    config_d.mkdir()
    root.write_text('include "config.d/90-user-extra.kdl"\n', encoding="utf-8")
    (config_d / "90-user-extra.kdl").write_text(
        'output "HDMI-A-1" {\n    mode "1920x1080@60.000"\n}\n', encoding="utf-8"
    )
    payload = {
        "primary": "HDMI-A-1",
        "outputs": [
            {"name": "HDMI-A-1", "mode": "1920x1080@60.000", "transform": "normal", "x": 0, "y": 0}
        ],
    }
    result = _run_cli(
        ["monitors", "--apply", json.dumps(payload)],
        env_extra=_apply_env(root, tmp / "niri.log"),
        fake_bin={"niri": FAKE_NIRI_APPLY},
    )
    assert result.returncode == 1
    assert "fuera de config.d/15-outputs.kdl" in result.stderr


def test_apply_preserves_disconnected_output_blocks() -> None:
    cli = _load_cli()
    tmp = Path(tempfile.mkdtemp())
    root = tmp / "config.kdl"
    block = cli.OutputBlock(
        name="DP-2", mode="2560x1440@120.000", scale=1,
        transform="normal", x=-2560, y=0, primary=False, vrr=False,
    )
    cli.write_output_configs(root, {"DP-2": block})
    payload = {
        "primary": "HDMI-A-1",
        "outputs": [
            {"name": "HDMI-A-1", "mode": "1920x1080@60.000", "transform": "normal", "x": 1024, "y": 0}
        ],
    }
    result = _run_cli(
        ["monitors", "--apply", json.dumps(payload)],
        env_extra=_apply_env(root, tmp / "niri.log"),
        fake_bin={"niri": FAKE_NIRI_APPLY},
    )
    assert result.returncode == 0, result.stderr
    text = cli.output_config_path(root).read_text(encoding="utf-8")
    assert 'output "DP-2" {' in text
    assert "position x=-2560 y=0" in text
```

- [x] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest -q tests/test_niri_monitors_cli.py -k "apply"`

Expected: FAIL con `Unknown command: monitors` o sin `monitor_apply`.

- [x] **Step 3: Implement `build_monitor_blocks()` y `monitor_apply()`**

`build_monitor_blocks` debe lanzar `ValueError` con mensajes en español para: payload no objeto, falta `primary`, `outputs` no lista, nombres duplicados, `primary` ausente, output desconocido, modo no disponible, transformación no válida, `x/y` no enteros —rechazar `bool`—. Debe construir `OutputBlock` con `scale`/`vrr` tomados de la salida viva, ordenar el bloque `primary` primero, luego el resto del payload y finalmente los bloques existentes no incluidos en el payload. `monitor_apply` debe verificar `detect_compositor() == "niri"`, ejecutar `niri msg --json outputs`, rechazar `foreign_output_files(niri_config_path())`, construir bloques, llamar a `write_output_configs`, `reload_niri_config()` y `run([niri, "msg", "action", "focus-monitor", primary])`. Escribir errores a `stderr` con prefijo `monitores: `. Devolver `1` en error y `0` al éxito. En `main()`, aceptar `monitors --apply <json>`.

- [x] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/pytest -q tests/test_niri_monitors_cli.py`

Expected: PASS.

---

### Task 4: `primary-output` honra el monitor elegido

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_niri_monitors_cli.py`

**Interfaces:**
- Consumes: `configured_primary_output()`, `_niri_outputs_map()`, `_niri_output_enabled()`, `_niri_output_position()` y `primary_output_niri_fallback()` de Task 2.
- Produces: comportamiento nuevo de `primary_output_niri()`.

- [x] **Step 1: Write the failing tests**

Agregar:

```python
def test_primary_output_uses_configured_monitor_over_top_left() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    cli.write_output_configs(
        root,
        {
            "HDMI-A-1": cli.OutputBlock(
                name="HDMI-A-1", mode="1920x1080@60.000", scale=1,
                transform="normal", x=1024, y=0, primary=True, vrr=False,
            )
        },
    )
    result = _run_cli(
        ["primary-output"],
        env_extra={"NIRI_SOCKET": "/run/user/1000/niri.sock", "NIRI_CONFIG": str(root)},
        fake_bin={"niri": FAKE_NIRI_OUTPUTS},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "HDMI-A-1"


def test_primary_output_ignores_configured_but_disconnected_monitor() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    cli.write_output_configs(
        root,
        {
            "eDP-1": cli.OutputBlock(
                name="eDP-1", mode="1920x1080@60.000", scale=1,
                transform="normal", x=0, y=0, primary=True, vrr=False,
            )
        },
    )
    result = _run_cli(
        ["primary-output"],
        env_extra={"NIRI_SOCKET": "/run/user/1000/niri.sock", "NIRI_CONFIG": str(root)},
        fake_bin={"niri": FAKE_NIRI_OUTPUTS},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "DP-1"
```

- [x] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest -q tests/test_niri_monitors_cli.py -k "primary_output"`

Expected: primer test FAIL devolviendo `DP-1`.

- [x] **Step 3: Refactorizar `primary_output_niri()`**

Reutilizar `primary_output_niri_fallback(outs)` y `_niri_output_position(info)` de Task 2. `primary_output_niri()` debe usar el mismo probe, llamar a `configured_primary_output(outs)` y devolver ese nombre sólo si está en `outs` y `_niri_output_enabled()` es `True`; si no, delegar al fallback.

- [x] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/pytest -q tests/test_niri_monitors_cli.py tests/test_caparazon_wm.py -k "primary_output"`

Expected: PASS, incluidos los tests antiguos de KDE.

---

### Task 5: Registrar la sección en `NiriConfigsPanel`

**Files:**
- Modify: `modules/secondmenu/NiriConfigsPanel.qml`
- Test: `tests/test_niri_configs_panel.py`

**Interfaces:**
- Consumes: `SegmentedChoice`, `MonitorsPanel.qml` creado en Task 6.
- Produces: sección `monitores` y componente `monitorComponent`.

- [x] **Step 1: Write the failing tests**

Agregar a `tests/test_niri_configs_panel.py`:

```python
def test_the_panel_registers_the_monitors_section() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '{ key: "monitores", label: "Monitores" }' in contents


def test_the_panel_resolves_the_monitors_component() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert 'if (key === "monitores")' in contents
    assert "return monitorComponent" in contents


def test_the_wrapper_mounts_the_monitors_panel() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "MonitorsPanel" in contents
```

- [x] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest -q tests/test_niri_configs_panel.py -k monitors`

Expected: FAIL.

- [x] **Step 3: Registrar la sección**

Agregar `{ key: "monitores", label: "Monitores" }` a `sections`, la rama `if (key === "monitores") return monitorComponent;` en `componentFor`, y un `Component { id: monitorComponent; MonitorsPanel { anchors.fill: parent } }`. No cambiar el default `tab`.

- [x] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/pytest -q tests/test_niri_configs_panel.py`

Expected: PASS.

---

### Task 6: Panel QML de monitores

**Files:**
- Create: `modules/secondmenu/MonitorsPanel.qml`
- Test: `tests/test_monitors_panel.py`

**Interfaces:**
- Consumes: `caparazon-wm monitors`, `caparazon-wm monitors --apply <json>`, `SegmentedChoice`.
- Produces: properties `outputs`, `draft`, `selectedName`, `primaryName`, `pendingJson`, `errorMessage`, `noticeMessage`, `applying`.

- [x] **Step 1: Write the failing tests**

Create `tests/test_monitors_panel.py`:

```python
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "MonitorsPanel.qml"


def test_monitors_panel_reads_and_applies_through_the_cli() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"monitors"' in contents
    assert '"--apply"' in contents
    assert "root.pendingJson" in contents
    assert "JSON.stringify" in contents


def test_monitors_panel_does_not_talk_to_the_system() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert ".config/niri" not in contents
    assert "niri msg" not in contents
    assert "FileView" not in contents
    assert "QtQuick.Controls" not in contents


def test_monitors_panel_exposes_all_controls() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '"Monitores"' in contents
    assert '"Principal"' in contents
    assert '"Resolución y tasa"' in contents
    assert '"Rotación"' in contents
    assert '"Posición"' in contents
    assert '"Aplicar"' in contents
    assert "SegmentedChoice" in contents
    assert "Flickable" in contents
    assert "errorMessage" in contents
    assert "noticeMessage" in contents
```

- [x] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/pytest -q tests/test_monitors_panel.py`

Expected: FAIL porque el archivo no existe.

- [x] **Step 3: Implementar `MonitorsPanel.qml`**

Crear un `Item` con imports `Quickshell`, `Quickshell.Io`, `QtQuick` y `"../../theme"`. `Component.onCompleted` lanza `load.running = true`. `applyState(payload)` parsea JSON y llena `outputs`, `selectedName` —primary o primero—, `primaryName` y `draft` —un objeto por output con `mode`, `transform`, `x`, `y` del estado—. `patchSelected(changes)` clona `draft` vía `JSON.parse(JSON.stringify(...))`, aplica cambios y lo reasigna. `prepareApply()` construye `{primary: root.primaryName, outputs: [...]}` desde `draft` y asigna `pendingJson = JSON.stringify(payload)` antes de lanzar `apply.running = true`. UI: fila de chips de monitores con `Repeater` y `MouseArea`; etiqueta con `label`; botón **Principal**; lista `Flickable` de `selectedOutput().modes` con `Repeater` y `MouseArea`; `SegmentedChoice` con opciones `Normal/90°/180°/270°` mapeadas a `normal/90/180/270`; dos `TextInput` con `IntValidator` para `x` e `y` conectados a `onEditingFinished`; botón **Aplicar** y footer con error/aviso. Sin `QtQuick.Controls`. Usar `Theme` para colores, fuentes y radius.

- [x] **Step 4: Run tests and qmllint**

Run: `.venv/bin/pytest -q tests/test_monitors_panel.py && /usr/lib/qt6/bin/qmllint modules/secondmenu/MonitorsPanel.qml`

Expected: PASS; qmllint sin errores.

---

### Task 7: Verificación nativa y QA visual

**Files:**
- No product code changes expected; corregir sólo lo que falle.

**Interfaces:**
- Consumes: todos los comandos y properties anteriores.

- [x] **Step 1: Run full automated checks**

Run:

```bash
.venv/bin/pytest -q --tb=line
python3 -m py_compile integration/bin/caparazon-wm.py
/usr/lib/qt6/bin/qmllint modules/secondmenu/NiriConfigsPanel.qml modules/secondmenu/MonitorsPanel.qml
.venv/bin/ruff check tests/test_niri_monitors_cli.py tests/test_monitors_panel.py tests/test_niri_configs_panel.py
```

Expected: pytest PASS con la cuenta nueva; `py_compile` sin salida; qmllint `errors=0`; ruff PASS en los tests nuevos/modificados.

- [x] **Step 2: Install the CLI used by QML and back up niri config**

Run:

```bash
cp integration/bin/caparazon-wm.py /home/ezku/.local/bin/caparazon-wm
chmod +x /home/ezku/.local/bin/caparazon-wm
stamp=$(date +%Y%m%d-%H%M%S)
cp -a /home/ezku/.config/niri/config.kdl "/home/ezku/.config/niri/config.kdl.bak-$stamp"
cp -a /home/ezku/.config/niri/config.d "/home/ezku/.config/niri/config.d.bak-$stamp"
command -v caparazon-wm
caparazon-wm monitors
caparazon-wm primary-output
```

Expected: `caparazon-wm monitors` imprime JSON con dos outputs; `primary-output` devuelve el monitor configurado o el fallback.

- [x] **Step 3: QA visual instrumentado**

Abrir el submenú de Caparazón, entrar a **Niri configs → Monitores** y capturar con ImageMagick:

```bash
magick import -window root /tmp/niri-monitors-tab.png
```

Verificar que se vean los dos monitores, modos, rotación, posición y botón **Aplicar**. Probar selección de **HDMI-A-1** como principal sin aplicar y confirmar que el state cambia en pantalla. Cerrar el submenú.

- [x] **Step 4: QA de persistencia con valores actuales**

Ejecutar un apply con los valores reales actuales —HDMI-A-1 principal, `1920x1080@60.000`, `normal`, `x=1024 y=0`; DP-1 `1024x768@60.004`, `normal`, `x=0 y=0`— y verificar:

```bash
caparazon-wm monitors
caparazon-wm primary-output
niri msg --json outputs
git diff --check
```

Expected: `primary-output` devuelve `HDMI-A-1`; `niri msg --json outputs` conserva modos y posiciones; `git diff --check` limpio. No ejecutar commits.

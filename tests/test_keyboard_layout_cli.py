"""Contrato del subcomando `keyboard-layout` de caparazon-wm."""

from __future__ import annotations

import importlib.util
import json
import os
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
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


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
        bindir = Path(tempfile.mkdtemp(prefix="cwm-keyboard-"))
        for name, body in fake_bin.items():
            _write_exec(bindir / name, body)
        env["PATH"] = str(bindir) + os.pathsep + env.get("PATH", "")
    return subprocess.run(  # noqa: S603
        ["python3", str(CLI), *args],  # noqa: S607
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )


def _keyboard_env(tmp_path: Path) -> dict[str, str]:
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    return {"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config")}


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


def test_catalog_groups_spanish_latin_america_as_a_layout() -> None:
    cli = _load_cli()
    languages = cli.keyboard_layout_catalog()
    spanish = next(item for item in languages if item["label"] == "Español")

    assert {"layout": "es", "variant": "", "label": "España"} in spanish["options"]
    assert {
        "layout": "latam",
        "variant": "",
        "label": "Latinoamérica",
    } in spanish["options"]


def test_catalog_covers_the_common_languages() -> None:
    cli = _load_cli()

    labels = [item["label"] for item in cli.keyboard_layout_catalog()]

    assert labels == [
        "Español",
        "Inglés",
        "Portugués",
        "Francés",
        "Alemán",
        "Italiano",
        "Japonés",
    ]


def test_keyboard_layout_label_uses_the_catalog() -> None:
    cli = _load_cli()

    assert cli.keyboard_layout_label("latam", "") == "Español · Latinoamérica"
    assert cli.keyboard_layout_label("us", "intl") == (
        "Inglés · EE. UU., internacional"
    )
    assert cli.keyboard_layout_label("xx", "yy") == "Personalizada: xx/yy"


def test_keyboard_layout_known_requires_an_exact_catalog_match() -> None:
    cli = _load_cli()

    assert cli.keyboard_layout_known("es", "")
    assert not cli.keyboard_layout_known("es", "latam")
    assert not cli.keyboard_layout_known("xx", "")


def test_keyboard_layout_state_serializes_the_catalog() -> None:
    cli = _load_cli()
    state = cli.KeyboardLayoutState(
        layout="es",
        variant="",
        label="Español · España",
        configured=True,
        languages=cli.keyboard_layout_catalog(),
    )

    payload = json.loads(state.to_json())

    assert payload["layout"] == "es"
    assert payload["variant"] == ""
    assert payload["label"] == "Español · España"
    assert payload["configured"] is True
    assert payload["languages"][0]["label"] == "Español"


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


def test_set_updates_layout_variant_and_keeps_options() -> None:
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

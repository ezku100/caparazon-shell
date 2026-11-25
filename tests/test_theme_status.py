"""Pruebas del comando de sólo lectura ``caparazon-wm theme status``."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType

    import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLI = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-wm.py"


def _load_cli() -> ModuleType:
    spec = importlib.util.spec_from_file_location("caparazon_wm_theme", CLI)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _state_file(home: Path) -> Path:
    return home / ".cache" / "accent-theme" / "niri-state.json"


def test_theme_status_reports_a_missing_state(tmp_path: Path) -> None:
    cli = _load_cli()

    payload = json.loads(cli.theme_status({"HOME": str(tmp_path)}))

    assert payload["status"] == "missing"
    assert payload["source"] is None


def test_theme_status_returns_the_published_state(tmp_path: Path) -> None:
    cli = _load_cli()
    target = _state_file(tmp_path)
    target.parent.mkdir(parents=True)
    _ = target.write_text(
        json.dumps(
            {
                "source": "waywallen",
                "reference": "66423",
                "wallpaperId": "66423",
                "sourceColor": "#ec1413",
                "generatedAt": "2026-11-24T10:00:00Z",
                "status": "ok",
            }
        ),
        encoding="utf-8",
    )

    payload = json.loads(cli.theme_status({"HOME": str(tmp_path)}))

    assert payload["source"] == "waywallen"
    assert payload["wallpaperId"] == "66423"
    assert payload["sourceColor"] == "#ec1413"
    assert payload["status"] == "ok"


def test_theme_status_respects_xdg_cache_home(tmp_path: Path) -> None:
    cli = _load_cli()
    target = tmp_path / "cache" / "accent-theme" / "niri-state.json"
    target.parent.mkdir(parents=True)
    _ = target.write_text('{"source": "kde", "status": "ok"}', encoding="utf-8")

    payload = json.loads(
        cli.theme_status(
            {"HOME": str(tmp_path / "home"), "XDG_CACHE_HOME": str(tmp_path / "cache")}
        )
    )

    assert payload["source"] == "kde"


def test_theme_status_survives_an_invalid_file(tmp_path: Path) -> None:
    cli = _load_cli()
    target = _state_file(tmp_path)
    target.parent.mkdir(parents=True)
    _ = target.write_text("no-json", encoding="utf-8")

    payload = json.loads(cli.theme_status({"HOME": str(tmp_path)}))

    assert payload["status"] == "invalid"


def test_main_dispatches_theme_status(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cli = _load_cli()
    target = _state_file(tmp_path)
    target.parent.mkdir(parents=True)
    _ = target.write_text('{"source": "waywallen", "status": "ok"}', encoding="utf-8")
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.delenv("XDG_CACHE_HOME", raising=False)

    code = cli.main(["theme", "status"])

    assert code == 0
    assert json.loads(capsys.readouterr().out)["source"] == "waywallen"

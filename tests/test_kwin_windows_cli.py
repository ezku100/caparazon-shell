"""Contrato del backend KWin de ventanas de caparazon-wm."""

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
    spec = importlib.util.spec_from_file_location("caparazon_wm_windows", CLI)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _write_cache(home: Path, windows: object) -> Path:
    cache = home / ".cache" / "ezku-desktops.json"
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(
        json.dumps(
            {
                "active": {"class": "kitty", "caption": "Terminal"},
                "windows": windows,
            }
        ),
        encoding="utf-8",
    )
    return cache


def test_windows_state_kwin_accepts_bridge_string_ids(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """El bridge KWin publica IDs como strings, no como objetos."""
    monkeypatch.setenv("HOME", str(tmp_path))
    _write_cache(tmp_path, ["kitty", "limusic-app"])
    cli = _load_cli()

    assert cli.windows_state_kwin() == {
        "appId": "kitty",
        "title": "Terminal",
        "appIds": ["kitty", "limusic-app"],
    }


def test_windows_state_kwin_keeps_bridge_dict_support(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """El formato dict histórico debe seguir funcionando."""
    monkeypatch.setenv("HOME", str(tmp_path))
    _write_cache(tmp_path, [{"class": "kitty"}, {"appId": "dolphin"}])
    cli = _load_cli()

    assert cli.windows_state_kwin()["appIds"] == ["kitty", "dolphin"]


def test_windows_cache_signature_changes_with_contents(tmp_path: Path) -> None:
    """El watcher debe detectar cambios de contenido del caché."""
    cli = _load_cli()
    cache = _write_cache(tmp_path, ["kitty"])
    first = cli.windows_cache_signature(cache)

    _write_cache(tmp_path, ["kitty", "dolphin"])
    assert cli.windows_cache_signature(cache) != first


def test_watch_windows_kwin_uses_cache_not_kwin_journal() -> None:
    source = CLI.read_text(encoding="utf-8")
    start = source.index("def watch_windows() -> int:")
    end = source.index("\ndef ", start + 1)
    body = source[start:end]

    assert "journalctl" not in body
    assert "windows_cache_signature" in body

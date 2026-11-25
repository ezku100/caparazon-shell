"""Pruebas de la sincronización de los temas de KDE con niri y con GTK."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType

    import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLI = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-wm.py"


def _load_cli() -> ModuleType:
    spec = importlib.util.spec_from_file_location("caparazon_wm_sync", CLI)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_read_kde_themes_returns_icons_and_cursor(tmp_path: Path) -> None:
    cli = _load_cli()
    kdeglobals = tmp_path / "kdeglobals"
    _ = kdeglobals.write_text(
        "[Icons]\nTheme=Tela-dark\n\n[Cursor]\ntheme=Breeze_Cursor\n",
        encoding="utf-8",
    )

    icons, cursor = cli.read_kde_themes(kdeglobals)

    assert icons == "Tela-dark"
    assert cursor == "Breeze_Cursor"


def test_read_kde_themes_without_file_is_empty(tmp_path: Path) -> None:
    cli = _load_cli()

    assert cli.read_kde_themes(tmp_path / "kdeglobals") == ("", "")


def test_write_gtk_setting_keeps_the_other_keys(tmp_path: Path) -> None:
    cli = _load_cli()
    settings = tmp_path / "settings.ini"
    _ = settings.write_text(
        "[Settings]\ngtk-theme-name=Adwaita\ngtk-icon-theme-name=Old\n",
        encoding="utf-8",
    )

    cli.write_gtk_setting(settings, "gtk-icon-theme-name", "Tela-dark")

    contents = settings.read_text(encoding="utf-8")
    assert "gtk-theme-name=Adwaita" in contents
    assert "gtk-icon-theme-name=Tela-dark" in contents
    assert "gtk-icon-theme-name=Old" not in contents


def test_write_gtk_setting_creates_the_settings_section(tmp_path: Path) -> None:
    cli = _load_cli()
    settings = tmp_path / "settings.ini"

    cli.write_gtk_setting(settings, "gtk-cursor-theme-name", "Breeze_Cursor")

    contents = settings.read_text(encoding="utf-8")
    assert "[Settings]" in contents
    assert "gtk-cursor-theme-name=Breeze_Cursor" in contents


def test_kde_theme_sync_pushes_the_kde_themes_to_niri_and_gtk(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cli = _load_cli()
    config_home = tmp_path / "config"
    _ = config_home.mkdir()
    _ = (config_home / "kdeglobals").write_text(
        "[Icons]\nTheme=Tela-dark\n\n[Cursor]\ntheme=Breeze_Cursor\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("XDG_CONFIG_HOME", str(config_home))
    applied: list[tuple[str, str]] = []

    def fake_icons(name: str) -> Path:
        applied.append(("icons", name))
        return tmp_path / "niri-icons"

    def fake_cursor(name: str) -> Path:
        applied.append(("cursor", name))
        return tmp_path / "niri-cursor"

    monkeypatch.setattr(cli, "detect_compositor", lambda: "niri")
    monkeypatch.setattr(cli, "write_icon_theme", fake_icons)
    monkeypatch.setattr(cli, "write_cursor_theme", fake_cursor)
    monkeypatch.setattr(cli, "reload_niri_config", lambda: 0)

    code = cli.kde_theme_sync()

    assert code == 0
    assert applied == [("icons", "Tela-dark"), ("cursor", "Breeze_Cursor")]
    gtk3 = (config_home / "gtk-3.0" / "settings.ini").read_text(encoding="utf-8")
    gtk4 = (config_home / "gtk-4.0" / "settings.ini").read_text(encoding="utf-8")
    for contents in (gtk3, gtk4):
        assert "gtk-icon-theme-name=Tela-dark" in contents
        assert "gtk-cursor-theme-name=Breeze_Cursor" in contents

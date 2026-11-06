"""Contrato del estilo de color activo de la shell."""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
THEME_STYLE = REPOSITORY_ROOT / "theme" / "ThemeStyle.qml"
PALETTE = REPOSITORY_ROOT / "theme" / "MatugenPalette.qml"
QMLDIR = REPOSITORY_ROOT / "theme" / "qmldir"
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "ShellConfigPanel.qml"


def test_theme_style_knows_the_three_styles() -> None:
    contents = THEME_STYLE.read_text(encoding="utf-8")

    for name in (
        "material",
        "oled",
        "perla",
        "colors-oled.json",
        "colors-perla.json",
    ):
        assert name in contents


def test_theme_style_persists_in_the_config_dir() -> None:
    contents = THEME_STYLE.read_text(encoding="utf-8")

    assert "/.config/caparazon" in contents
    assert "style.json" in contents


def test_palette_follows_the_active_style() -> None:
    contents = PALETTE.read_text(encoding="utf-8")

    assert "ThemeStyle.paletteFile" in contents
    assert "onPathChanged" in contents


def test_qmldir_registers_the_style_singleton() -> None:
    assert "singleton ThemeStyle" in QMLDIR.read_text(encoding="utf-8")


def test_the_panel_switches_the_style() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "ThemeStyle.setStyle(" in contents
    assert "ThemeStyle.palettePathFor(" in contents

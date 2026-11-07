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


def test_the_panel_offers_the_dock_modes() -> None:
    """El panel alterna entre dock dinámico y anclado."""
    contents = PANEL.read_text(encoding="utf-8")

    assert '"dynamic"' in contents
    assert '"anchored"' in contents
    assert "setDockAnchored(" in contents


def test_the_panel_reads_the_dock_mode_from_its_config() -> None:
    """El estado del dock vive en dock.json, junto al del estilo."""
    contents = PANEL.read_text(encoding="utf-8")

    assert "dock.json" in contents
    assert "property bool dockPinned: false" in contents
    assert "watchChanges: true" in contents


def test_the_panel_patches_only_the_dock_mode() -> None:
    """El parche es atómico y conserva el resto de dock.json."""
    contents = PANEL.read_text(encoding="utf-8")

    assert '"python3"' in contents
    assert "os.replace(tmp, path)" in contents
    assert "data['dockPinned'] = wanted" in contents
    assert "writeAdapter" not in contents


def test_the_style_fallback_waits_for_the_palettes_to_settle() -> None:
    """El regreso a Material espera a que las tres paletas se resuelvan.

    Durante la carga una paleta pendiente se ve igual que una ausente:
    decidir antes pisaba el estilo guardado (OLED volvía a Material) al
    abrir el panel.
    """
    contents = PANEL.read_text(encoding="utf-8")

    assert "onLoadFailed" in contents
    assert "palettesSettled" in contents
    assert "if (!root.palettesSettled)" in contents
    assert "availablePalettes.indexOf(ThemeStyle.style)" in contents
    assert contents.count('ThemeStyle.setStyle("material")') == 1
    assert contents.index("if (!root.palettesSettled)") < contents.index(
        'ThemeStyle.setStyle("material")'
    )


def test_the_auto_mode_follows_the_hour() -> None:
    """Mañana Perla, tarde Material, noche OLED, revisado cada medio minuto."""
    contents = THEME_STYLE.read_text(encoding="utf-8")

    assert "property bool autoStyle: false" in contents
    assert "function styleForHour(hour)" in contents
    assert "hour >= 6 && hour < 12" in contents
    assert "hour >= 12 && hour < 19" in contents
    assert 'return "perla"' in contents
    assert 'return "material"' in contents
    assert 'return "oled"' in contents
    assert "new Date().getHours()" in contents
    assert "interval: 30000" in contents
    assert "running: root.autoStyle" in contents


def test_the_auto_mode_is_saved_with_the_style() -> None:
    contents = THEME_STYLE.read_text(encoding="utf-8")

    assert "property bool auto: false" in contents
    assert '\\"auto\\":' in contents
    assert "root.autoStyle = adapter.auto === true" in contents


def test_the_panel_offers_the_day_night_mode() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    control = REPOSITORY_ROOT / "modules" / "secondmenu" / "SegmentedChoice.qml"

    assert "Modo día/noche" in contents
    assert "ThemeStyle.setAutoStyle(" in contents
    assert '"auto"' in contents
    assert '"manual"' in contents
    assert "SegmentedChoice {" in contents
    assert control.exists(), "el control segmentado debe existir"


def test_choosing_a_style_leaves_the_auto_mode() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert contents.index("ThemeStyle.setAutoStyle(false)") < contents.index(
        "ThemeStyle.setStyle(row.modelData.key)"
    )


def test_the_fallback_does_not_fight_the_auto_mode() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "if (ThemeStyle.autoStyle)" in contents

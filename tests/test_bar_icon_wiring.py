"""Contrato del cableado de los iconos de la barra.

Los cuatro QML de la barra son QML puro y no se pueden probar sin levantar la
shell, asi que aqui se comprueba lo que no debe volver por descuido: que
ninguno dibuje glifos de Nerd Font, que todos resuelvan el icono con
IconResolver y que la dependencia de la fuente haya desaparecido de verdad.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

BAR = REPOSITORY_ROOT / "modules" / "bar"

QML_FILES = [
    BAR / "PowerMenu.qml",
    BAR / "VolumeChip.qml",
    BAR / "PowerProfile.qml",
    BAR / "PowerButton.qml",
]

THEME = REPOSITORY_ROOT / "theme" / "Theme.qml"
README = REPOSITORY_ROOT / "README.md"
INSTALL = REPOSITORY_ROOT / "install.sh"


@pytest.mark.parametrize("path", QML_FILES, ids=lambda p: p.name)
def test_the_bar_no_longer_draws_nerd_font_glyphs(path: Path) -> None:
    """Un glifo de Nerd Font vuelve a romper el objetivo del cambio."""
    contents = path.read_text(encoding="utf-8")

    assert "\\u{F" not in contents
    assert "Theme.fontIcon" not in contents


@pytest.mark.parametrize("path", QML_FILES, ids=lambda p: p.name)
def test_the_bar_resolves_its_icons_by_theme_name(path: Path) -> None:
    """El icono sale del tema activo, como el resto de la barra."""
    contents = path.read_text(encoding="utf-8")

    assert "IconResolver.firstOf(" in contents
    assert "BarIcons." in contents


def test_the_theme_no_longer_declares_a_nerd_font_family() -> None:
    """Sin glifos, la familia de la fuente no tiene ningun uso."""
    contents = THEME.read_text(encoding="utf-8")

    assert "fontIcon" not in contents


def test_the_readme_no_longer_requires_nerd_font() -> None:
    """Documentar una dependencia que no existe confunde al que instala."""
    contents = README.read_text(encoding="utf-8").lower()

    assert "nerd font" not in contents


def test_the_installer_no_longer_checks_nerd_font() -> None:
    """El instalador no debe avisar de una fuente que ya no se usa."""
    contents = INSTALL.read_text(encoding="utf-8")

    assert "require_nerd_font" not in contents
    assert "Nerd Font" not in contents

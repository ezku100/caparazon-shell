"""El tintado de los iconos tiene que acompañar al estilo activo.

En los estilos claros (Perla) la paleta trae `fgSurface` casi negro y
`fgSurfaceVariant` en gris cálido. Tañados con esa tinta neutra, los iconos
de la bandeja, el dock, el menú, el submenú, los recursos y el nombre de la
ventana quedaban negros sobre el papel y desentonaban con el acento.

La regla: sobre superficie clara los iconos llevan el color de énfasis, y no
se juega con intensidades del mismo (ni un acento más claro ni más apagado).
Sobre superficie oscura se mantiene la tinta de siempre: tinta clara para el
icono normal, tinta apagada para el secundario y la fuerte para el hover.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
THEME = REPOSITORY_ROOT / "theme" / "Theme.qml"

ICON_FILES = [
    REPOSITORY_ROOT / "modules" / "appmenu" / "AppMenu.qml",
    REPOSITORY_ROOT / "modules" / "appmenu" / "RailButton.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "ActiveWindow.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "BluetoothIndicator.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "Network.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "PowerButton.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "PowerMenu.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "PowerProfile.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "ResourceRing.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "Tray.qml",
    REPOSITORY_ROOT / "modules" / "bar" / "VolumeChip.qml",
    REPOSITORY_ROOT / "modules" / "dock" / "DockApp.qml",
    REPOSITORY_ROOT / "modules" / "dock" / "MusicButton.qml",
    REPOSITORY_ROOT / "modules" / "secondmenu" / "MusicPanel.qml",
    REPOSITORY_ROOT / "modules" / "secondmenu" / "SystemMonitorPanel.qml",
]


def theme_contents() -> str:
    return THEME.read_text(encoding="utf-8")


def property_body(contents: str, name: str) -> str:
    """Devuelve el cuerpo de una propiedad del tema, sin comerse la siguiente."""
    match = re.search(
        rf"readonly property (?:color|bool) {name}:(.*?)(?=\n\s*(?:readonly |property )\w|\Z)",
        contents,
        re.DOTALL,
    )

    assert match is not None, f"{name} no está en el tema"
    return match.group(1)


def test_the_theme_exposes_the_icon_tint_tokens() -> None:
    """Los tres tonos de tintado viven en el tema, no en cada widget."""
    contents = theme_contents()

    assert "readonly property color iconTint:" in contents
    assert "readonly property color iconTintMuted:" in contents
    assert "readonly property color iconTintHover:" in contents


def test_the_icon_tint_follows_the_accent_on_light_surfaces() -> None:
    """Sobre papel los iconos llevan el color de énfasis."""
    contents = theme_contents()
    tint = property_body(contents, "iconTint")

    assert "lightSurface" in tint
    assert "m3Primary" in tint
    assert "m3OnSurfaceVariant" not in tint


def test_the_muted_icon_tint_also_follows_the_accent() -> None:
    """El icono apagado tampoco inventa intensidades del acento."""
    contents = theme_contents()
    tint = property_body(contents, "iconTintMuted")

    assert "lightSurface" in tint
    assert "m3Primary" in tint


def test_the_light_surface_is_detected_from_the_palette() -> None:
    """La decisión se toma con la superficie de la paleta, no por nombre."""
    contents = theme_contents()
    light = property_body(contents, "lightSurface")

    assert "m3SurfaceContainer" in light
    assert "perla" not in light


def icon_tint_expressions(contents: str) -> list[str]:
    """Devuelve las expresiones con las que cada widget tiñe sus iconos.

    El tinte puede venir en la propia capa (`colorizationColor`) o en una
    propiedad que la capa usa (`iconColor`), así que se recogen las dos.
    """
    expressions: list[str] = []
    lines = contents.splitlines()

    for index, line in enumerate(lines):
        if "colorizationColor:" not in line and "iconColor:" not in line:
            continue
        expressions.append("\n".join(lines[index : index + 5]))

    return expressions


@pytest.mark.parametrize("widget", ICON_FILES, ids=lambda path: path.name)
def test_the_widgets_tint_their_icons_with_the_theme_tokens(widget: Path) -> None:
    """Ningún widget tiñe iconos con la tinta neutra de su cuenta."""
    contents = widget.read_text(encoding="utf-8")
    tints = icon_tint_expressions(contents)

    assert tints, f"{widget.name} no tiñe iconos"

    for tint in tints:
        assert "Theme.textDim" not in tint
        assert "Theme.text" not in tint
        assert "Theme.m3OnSurfaceVariant" not in tint


@pytest.mark.parametrize("widget", ICON_FILES, ids=lambda path: path.name)
def test_the_widgets_use_the_icon_tint_tokens(widget: Path) -> None:
    """Los iconos se tiñen con los tokens del tema, no con colores sueltos."""
    contents = widget.read_text(encoding="utf-8")
    tints = icon_tint_expressions(contents)

    assert any("Theme.iconTint" in tint for tint in tints)


def test_the_active_states_keep_the_ink_of_the_accent() -> None:
    """Sobre una píldora de acento el icono sigue siendo el color de encima."""
    contents = theme_contents()

    assert "readonly property color m3OnPrimary:" in contents

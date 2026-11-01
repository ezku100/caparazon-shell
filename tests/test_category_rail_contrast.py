"""El raíl de categorías tiene que verse sobre la tarjeta.

La tarjeta del menú y la del submenú se pintan con `Theme.surface`, que es
el tono más bajo de superficie. El raíl usaba `Theme.m3SurfaceContainerLow`,
un tono casi idéntico: entre `#21191f` (raíl) y `#181117` (tarjeta) el
contraste da 1.08:1, así que la sección de categorías se perdía contra el
fondo y el menú y el submenú parecían no tener raíl.

El raíl tiene que ser un contenedor elevado. Sin borde: el color del
contenedor ya lo separa de la tarjeta y el borde lo sobraba.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
APP_MENU = REPOSITORY_ROOT / "modules" / "appmenu" / "AppMenu.qml"
SECOND_MENU = REPOSITORY_ROOT / "modules" / "secondmenu" / "SecondMenu.qml"

RAIL_PROPERTIES = re.compile(r"id:\s*rail\b[^\n]*\n(.*?)\n\s*Column\s*\{", re.DOTALL)


def rail_properties(menu: Path) -> str:
    """Devuelve las propiedades propias del raíl de categorías."""
    contents = menu.read_text(encoding="utf-8")
    match = RAIL_PROPERTIES.search(contents)

    assert match is not None, f"{menu.name} no tiene raíl"
    return match.group(1)


@pytest.mark.parametrize("menu", [APP_MENU, SECOND_MENU], ids=lambda path: path.name)
def test_the_category_rail_does_not_use_the_lowest_surface(menu: Path) -> None:
    """`m3SurfaceContainerLow` se confunde con el fondo de la tarjeta."""
    properties = rail_properties(menu)

    assert "m3SurfaceContainerLow" not in properties


@pytest.mark.parametrize("menu", [APP_MENU, SECOND_MENU], ids=lambda path: path.name)
def test_the_category_rail_is_a_raised_container(menu: Path) -> None:
    """El raíl se apoya en un tono de superficie por encima de la tarjeta."""
    properties = rail_properties(menu)

    assert "color: Theme.chip" in properties


@pytest.mark.parametrize("menu", [APP_MENU, SECOND_MENU], ids=lambda path: path.name)
def test_the_category_rail_has_no_border(menu: Path) -> None:
    """El color del contenedor basta; el borde estorba."""
    properties = rail_properties(menu)

    assert "border.width" not in properties
    assert "border.color" not in properties

"""Al cambiar de app rápido no puede quedar el fantasma de la anterior.

La píldora de selección y el color del nombre se apagaban con una
animación de 130 ms. Al saltar de una app a otra, la anterior seguía
iluminada mientras se apagaba y se veía como una sombra pegada.

El apagado tiene que ser inmediato; la entrada puede seguir siendo suave.
"""

from __future__ import annotations

import re
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
APP_TILE = REPOSITORY_ROOT / "modules" / "appmenu" / "AppTile.qml"
APP_MENU = REPOSITORY_ROOT / "modules" / "appmenu" / "AppMenu.qml"
RAIL_BUTTON = REPOSITORY_ROOT / "modules" / "appmenu" / "RailButton.qml"

BEHAVIOR = re.compile(
    r"Behavior on color \{\s*ColorAnimation \{(.*?)\}",
    re.DOTALL,
)


def behaviors(contents: str) -> list[str]:
    """Devuelve el cuerpo de cada `Behavior on color` del fichero."""
    return BEHAVIOR.findall(contents)


def test_the_app_tile_turns_off_the_selection_instantly() -> None:
    """La píldora de la app anterior no puede quedar encendida."""
    contents = APP_TILE.read_text(encoding="utf-8")
    blocks = behaviors(contents)

    assert blocks
    assert "root.active ? Theme.durFast : 0" in blocks[0]


def test_the_app_tile_turns_off_the_label_instantly() -> None:
    """El nombre de la app anterior tampoco se queda a medio apagar."""
    contents = APP_TILE.read_text(encoding="utf-8")
    blocks = behaviors(contents)

    assert len(blocks) >= 2
    assert "root.active ? Theme.durFast : 0" in blocks[1]


def test_the_emoji_and_clipboard_hover_turn_off_instantly() -> None:
    """Emojis y portapapeles tienen el mismo fondo con el mismo defecto."""
    contents = APP_MENU.read_text(encoding="utf-8")
    blocks = behaviors(contents)

    assert len(blocks) >= 2
    for block in blocks:
        assert "? Theme.durFast : 0" in block


def test_the_icon_does_not_stay_tilted_after_losing_the_selection() -> None:
    """El icono de la app anterior no se queda inclinado al apagarse."""
    contents = APP_TILE.read_text(encoding="utf-8")
    reset = re.search(r"id: resetTilt\b.*?duration:\s*(\S+)", contents, re.DOTALL)

    assert reset is not None
    assert reset.group(1) == "0"


def test_the_rail_pill_turns_off_instantly() -> None:
    """El raíl de categorías arrastra la misma estela al cambiar."""
    contents = RAIL_BUTTON.read_text(encoding="utf-8")
    blocks = behaviors(contents)

    assert blocks
    assert "Theme.durFast : 0" in blocks[0]

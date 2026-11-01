"""El chip de selección no puede ennegrecerse al cambiar de app.

En Qt, "transparent" es negro con alfa 0. Al interpolar el color de un chip
hacia "transparent", el fundido pasa por tonos oscuros: a mitad de camino el
chip se ve negro durante unos instantes. La opacidad sí interpola de forma
lineal, así que los chips se pintan siempre con su color y lo único que se
anima es la opacidad.

Al perder la selección el apagado además es inmediato: nada debe quedar
encendido de la app anterior.
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


def test_the_app_tile_chip_animates_opacity_not_color() -> None:
    """El chip de la app se enciende y apaga con opacidad."""
    contents = APP_TILE.read_text(encoding="utf-8")

    assert "color: Theme.chipHover" in contents
    assert "opacity: root.active ? 1 : 0" in contents
    assert "Behavior on opacity" in contents


def test_the_app_tile_chip_turns_off_instantly() -> None:
    """La app anterior no puede quedarse iluminada."""
    contents = APP_TILE.read_text(encoding="utf-8")
    pill = re.search(
        r"Behavior on opacity \{\s*NumberAnimation \{(.*?)\}",
        contents,
        re.DOTALL,
    )

    assert pill is not None
    assert "root.active ? Theme.durFast : 0" in pill.group(1)


def test_the_label_fades_without_going_through_black() -> None:
    """El nombre se apaga al instante y sus tonos son opacos."""
    contents = APP_TILE.read_text(encoding="utf-8")
    blocks = behaviors(contents)

    assert len(blocks) == 1
    assert "root.active ? Theme.durFast : 0" in blocks[0]
    assert "Theme.textDim" in contents


def test_the_emoji_and_clipboard_chips_animates_opacity() -> None:
    """Emojis y portapapeles tienen el mismo fondo con el mismo defecto."""
    contents = APP_MENU.read_text(encoding="utf-8")

    assert "opacity: emojiHover.hovered ? 1 : 0" in contents
    assert "opacity: clipHover.hovered ? 1 : 0" in contents


def test_the_rail_paints_selection_and_hover_in_two_layers() -> None:
    """El raíl separa selección y hover para no mezclar tonos."""
    contents = RAIL_BUTTON.read_text(encoding="utf-8")

    assert "color: Theme.m3Primary" in contents
    assert "opacity: root.selected ? 1 : 0" in contents
    assert "opacity: !root.selected && hover.hovered ? 1 : 0" in contents
    assert behaviors(contents) == []


def test_no_chip_in_the_menu_fades_through_black() -> None:
    """Ningún chip puede seguir animando su color hacia "transparent"."""
    for path in (APP_TILE, APP_MENU, RAIL_BUTTON):
        contents = path.read_text(encoding="utf-8")
        assert 'Theme.chipHover : "transparent"' not in contents

    assert behaviors(APP_MENU.read_text(encoding="utf-8")) == []


def test_the_icon_does_not_stay_tilted_after_losing_the_selection() -> None:
    """El icono de la app anterior no se queda inclinado al apagarse."""
    contents = APP_TILE.read_text(encoding="utf-8")
    reset = re.search(r"id: resetTilt\b.*?duration:\s*(\S+)", contents, re.DOTALL)

    assert reset is not None
    assert reset.group(1) == "0"

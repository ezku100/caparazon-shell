"""El contenido del dock tiene que dejar aire con el borde del cristal.

La fila del dock ocupa todo el alto del cristal (52 px) y dentro caben tres
tipos de pieza: la tarjeta de música (42 px), el icono de cada app (44 px) y
el botón de pin (52 px, el que marca el alto de la fila).

Qt 6 quitó la propiedad `alignment` de las filas, así que una `Row` deja a
sus hijos pegados arriba: la tarjeta de música se pegaba al borde superior y
parecía recortada, y el contador de ventanas, que se dibuja sobre la esquina
de su icono, se salía del cristal y lo partían por la mitad.

La fila no mueve a sus hijos en vertical, así que cada pieza se centra
calculando su `y`. Aquí se comprueba el contrato con los números que
declaran los propios QML: nada llega al borde del cristal.
"""

from __future__ import annotations

import re
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

DOCK = REPOSITORY_ROOT / "modules" / "dock" / "Dock.qml"
DOCK_APP = REPOSITORY_ROOT / "modules" / "dock" / "DockApp.qml"
MUSIC_WIDGET = REPOSITORY_ROOT / "modules" / "dock" / "MusicWidget.qml"
THEME = REPOSITORY_ROOT / "theme" / "Theme.qml"

# Aire mínimo entre el contenido del dock y el borde del cristal.
MIN_MARGIN = 3

# La forma de centrar un hijo dentro de la fila.
CENTERING = "y: Math.round((dockRow.height - height) / 2)"


def qml(path: Path) -> str:
    """Devuelve el contenido de un archivo QML del repositorio."""
    return path.read_text(encoding="utf-8")


def dock_row() -> str:
    """El bloque de la fila del dock, con sus hijos dentro."""
    contents = qml(DOCK)
    start = contents.index("id: dockRow")
    end = contents.index("\n            }", start)
    return contents[start:end]


def music_widget() -> str:
    """El bloque de la tarjeta de música dentro de la fila."""
    row = dock_row()
    start = row.index("MusicWidget {")
    end = row.index("\n                }", start)
    return row[start:end]


def delegate() -> str:
    """El bloque de la delegación que dibuja cada icono de app."""
    row = dock_row()
    start = row.index("delegate: DockApp {")
    end = row.index("\n                    }", start)
    return row[start:end]


def badge() -> str:
    """El rectángulo del contador de ventanas."""
    contents = qml(DOCK_APP)
    start = contents.index("visible: root.instanceCount > 1")
    return contents[start : contents.index("MouseArea {", start)]


def number(source: str, name: str) -> int:
    """El valor entero de una propiedad declarada en un bloque de QML."""
    match = re.search(rf"\b{name}:\s*(-?\d+)", source)
    assert match is not None, f"no se encuentra {name}"
    return int(match.group(1))


def dock_height() -> int:
    """El alto del cristal del dock, según el tema."""
    return number(qml(THEME), "dockHeight")


def row_height() -> int:
    """El alto de la fila: el grosor del cristal, que marca el tema."""
    contents = qml(DOCK)
    assert "height: dock.vertical ? parent.height : Theme.dockHeight" in contents
    return dock_height()


def top_offset(child_height: int) -> int:
    """Cuántos px deja la fila entre el borde superior y un hijo centrado."""
    return (row_height() - child_height) // 2


def test_the_dock_row_has_no_alignment_property() -> None:
    """Qt 6 no tiene `alignment` en las filas: asignarla rompe la carga.

    La fila alinea a sus hijos arriba, así que el centrado va en el `y` de
    cada pieza, no en una propiedad de la fila.
    """
    assert "alignment:" not in dock_row()


def test_the_dock_row_centers_its_items() -> None:
    """La tarjeta de música y los iconos se centran en la fila."""
    assert CENTERING in music_widget()
    assert CENTERING in delegate()


def test_the_music_card_keeps_its_distance_from_the_top_edge() -> None:
    """La tarjeta de música respira por arriba y por abajo.

    Se mide el alto de la tarjeta en horizontal: en columna el widget crece
    hacia abajo con los botones apilados.
    """
    music_height = number(qml(MUSIC_WIDGET), "cardHeight")
    top = top_offset(music_height)

    assert top >= MIN_MARGIN
    assert top + music_height <= row_height() - MIN_MARGIN


def test_the_window_badge_stays_inside_the_glass() -> None:
    """El contador de ventanas no se sale del cristal ni lo roza.

    El contador se dibuja sobre la esquina de su icono; si además sobresale
    hacia arriba, `contentClip` lo parte por la mitad contra el borde.
    """
    app_height = number(qml(DOCK_APP), "implicitHeight")
    badge_height = number(badge(), "height")
    badge_margin = number(badge(), "topMargin")
    top = top_offset(app_height) + badge_margin

    assert top >= MIN_MARGIN
    assert top + badge_height <= row_height()

"""Chip de música en la barra vertical: carátula centrada y sin desbordar.

El chip vive en el mismo ColumnLayout que el aviso; sin un tamaño preferido
el layout lo dejaba en 0 y la carátula se dibujaba pegada al borde y cortada.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MEDIA = REPOSITORY_ROOT / "modules" / "bar" / "MediaChip.qml"


def test_the_vertical_pill_is_a_centered_circle() -> None:
    contents = MEDIA.read_text(encoding="utf-8")

    assert "width: root.vertical ? 26 : root.width" in contents
    assert "height: root.vertical ? 26 : 30" in contents
    assert "radius: root.vertical ? width / 2 : 10" in contents
    assert "anchors.horizontalCenter: parent.horizontalCenter" in contents


def test_the_chip_enters_with_the_same_gesture_as_the_notice() -> None:
    contents = MEDIA.read_text(encoding="utf-8")

    assert "property real presence: active ? 1 : 0" in contents
    assert "scale: 0.84 + 0.16 * presence" in contents
    assert "property real slot: root.vertical && root.active ? 26 : 0" in contents
    assert "Layout.preferredHeight: root.vertical ? root.slot : root.height" in contents

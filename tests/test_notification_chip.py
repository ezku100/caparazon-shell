"""Chip de la notificación activa: icono de la app y centrado en la barra.

En vertical no hay sitio para el texto: el chip queda como un círculo con el
icono de la app que lanzó el aviso. Como el chip vive en un ColumnLayout, su
ancho tiene que ser preferido por el layout o éste lo deja en 0 y el aviso se
dibuja fuera de la barra.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CHIP = REPOSITORY_ROOT / "modules" / "bar" / "NotificationChip.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"


def test_the_icon_falls_back_to_the_notification_icon() -> None:
    """Sin appIcon se usa el icono genérico de notificación, no se deja vacío."""
    contents = CHIP.read_text(encoding="utf-8")

    assert "notification.appIcon" in contents
    assert "notifications-symbolic" in contents
    assert "IconResolver.firstOf(" in contents


def test_the_vertical_pill_is_a_centered_circle() -> None:
    contents = CHIP.read_text(encoding="utf-8")

    assert "width: root.vertical ? 26 : root.width" in contents
    assert "height: root.vertical ? 26 : 28" in contents
    assert "radius: root.vertical ? width / 2 : 9" in contents
    assert "anchors.horizontalCenter: parent.horizontalCenter" in contents


def test_the_vertical_chip_declares_its_preferred_size() -> None:
    """Sin preferidos el ColumnLayout lo deja en 0 y se sale de la barra.

    El alto sale de `slot`, que se anima: sin aviso es 0 para no reservar un
    hueco fijo entre el reloj y el chip de música.
    """
    contents = CHIP.read_text(encoding="utf-8")

    assert "Layout.preferredWidth: root.vertical" in contents
    assert "(root.active ? Theme.barHeight : 0)" in contents
    assert "Layout.preferredHeight: root.vertical ? root.slot : root.height" in contents
    assert "property real slot: root.vertical && root.active ? 26 : 0" in contents


def test_the_chip_enters_with_fade_pop_and_slide() -> None:
    """Un solo driver (presence) mueve fundido, escala con rebote y desliz."""
    contents = CHIP.read_text(encoding="utf-8")

    assert "property real presence: active ? 1 : 0" in contents
    assert "opacity: presence" in contents
    assert "scale: 0.84 + 0.16 * presence" in contents
    assert "transform: Translate {" in contents
    assert "easing.type: root.active ? Easing.OutBack : Easing.InCubic" in contents


def test_the_clock_slides_when_the_hole_is_animated() -> None:
    """`slot` animado: el ColumnLayout recoloca el reloj en cada frame."""
    contents = CHIP.read_text(encoding="utf-8")

    assert "Behavior on slot {" in contents

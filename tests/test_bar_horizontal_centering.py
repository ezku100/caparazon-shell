"""La barra horizontal centra sus módulos en la franja visible.

El `frame` mide `barHeight + shadowPad`, así que su centro vertical queda
6 px del lado interior: los módulos parecían pegados al borde en vez de
centrados. El ancla buena es el centro de la franja visible, y en el eje
vertical de la columna el centro del frame sí coincide con el de la barra.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
LAUNCHER_BUTTON = REPOSITORY_ROOT / "modules" / "bar" / "LauncherButton.qml"


def test_the_bar_defines_the_visible_vertical_center() -> None:
    """El centro vertical descuenta el aire de la sombra por abajo."""
    contents = BAR.read_text(encoding="utf-8")

    assert "readonly property real barCenterY" in contents
    assert "Theme.shadowPad + Theme.barHeight / 2" in contents
    assert "id: barCenterV" in contents


def test_the_horizontal_groups_hang_from_the_visible_center() -> None:
    """Los seis grupos horizontales se anclan al centro de la franja."""
    contents = BAR.read_text(encoding="utf-8")

    assert contents.count("verticalCenter: barCenterV.verticalCenter") == 6
    # El reloj ya no se centra en el frame (que incluye la sombra).
    assert "anchors.centerIn: parent" not in contents


def test_only_the_vertical_middle_group_uses_the_frame_center() -> None:
    """En vertical el frame ocupa todo el alto, así que su centro sirve."""
    contents = BAR.read_text(encoding="utf-8")

    assert contents.count("verticalCenter: parent.verticalCenter") == 1


def test_the_launcher_kanji_has_no_permanent_background() -> None:
    """El kanji va limpio: el círculo aparece sólo al pasar el puntero."""
    contents = LAUNCHER_BUTTON.read_text(encoding="utf-8")

    assert "root.vertical" not in contents
    assert "property bool vertical" not in contents
    assert 'hover.hovered ? Qt.lighter(Theme.chipHover, 1.45) : "transparent"' in contents


def test_the_horizontal_ends_keep_a_margin_from_the_lip() -> None:
    """El lanzador y el apagado no se pegan al filo del labio."""
    contents = BAR.read_text(encoding="utf-8")

    margin = "Theme.shadowPad + Theme.radiusTop + Theme.padH"
    assert f"readonly property int edgeMargin: {margin}" in contents
    # Un margen por extremo; el valor ya descuenta el labio del trazo.
    assert contents.count("Margin: bar.edgeMargin") == 2

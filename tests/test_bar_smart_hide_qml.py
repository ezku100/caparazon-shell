"""Contrato QML del modo dinámico de la barra.

Los tests de ``test_bar_smart_hide.py`` cubren el cálculo puro; éstos vigilan
el cableado: que la barra consulte ese módulo, que el puntero la devuelva y
que el interruptor de Configs persista el modo en display.json.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
THEME = REPOSITORY_ROOT / "theme" / "Theme.qml"
LAYOUT = REPOSITORY_ROOT / "theme" / "ShellLayout.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
SHELL = REPOSITORY_ROOT / "shell.qml"
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "ShellConfigPanel.qml"


def test_the_theme_declares_the_dynamic_bar_tokens() -> None:
    """El filo sensible y la gracia viven en el tema, como los del dock."""
    contents = THEME.read_text(encoding="utf-8")

    assert "property int barHotEdge: 6" in contents
    assert "property int barHideGrace: 600" in contents


def test_the_layout_persists_whether_the_bar_is_anchored() -> None:
    """El modo se guarda junto al resto de la disposición."""
    contents = LAYOUT.read_text(encoding="utf-8")

    assert "property bool barAnchored: true" in contents
    assert "root.barAnchored = adapter.barAnchored !== false" in contents
    assert '\\"barAnchored\\":' in contents
    assert "onBarAnchoredChanged: if (!root.syncing) root.save()" in contents
    assert "function setBarAnchored(value)" in contents


def test_the_shell_passes_the_mode_to_every_bar() -> None:
    """La barra de cada monitor sigue el modo elegido en Configs."""
    contents = SHELL.read_text(encoding="utf-8")

    assert "anchored: ShellLayout.barAnchored" in contents


def test_the_bar_uses_the_shared_smart_hide_calculation() -> None:
    """Estado, máscara y franja reservada salen del módulo puro."""
    contents = BAR.read_text(encoding="utf-8")

    assert '"BarSmartHide.js" as BarSmartHide' in contents
    assert "BarSmartHide.stateFor(bar.anchored, bar.pointerOnBar)" in contents
    assert "BarSmartHide.exclusiveZone(bar.anchored, Theme.barHeight)" in contents
    assert "BarSmartHide.maskRect(bar.smartState" in contents


def test_the_puck_reveals_the_bar_and_the_grace_hides_it() -> None:
    """El puntero la llama; al salir, una gracia evita cierres en falso."""
    contents = BAR.read_text(encoding="utf-8")

    assert "HoverHandler {" in contents
    assert "interval: Theme.barHideGrace" in contents
    assert "onTriggered: if (!bar.menuOpen && bar.pointerLeft)" in contents
    assert "onMenuOpenChanged: if (!menuOpen && pointerLeft)" in contents


def test_the_hover_detector_lives_outside_the_hit_area() -> None:
    """Vive en la raíz para que sus hermanos no le roben el hover."""
    contents = BAR.read_text(encoding="utf-8")
    hit_start = contents.index("id: hitArea")

    assert contents.count("HoverHandler {") == 1
    assert contents.index("HoverHandler {") > hit_start


def test_the_bar_only_appears_when_it_should() -> None:
    """Anclada siempre; dinámica sólo con el puntero encima."""
    contents = BAR.read_text(encoding="utf-8")

    assert (
        "bar.shown && (bar.anchored || bar.smartState === \"revealed\")" in contents
    )
    assert "onWantsRevealChanged: reveal = bar.wantsReveal ? 1 : 0" in contents


def test_the_configs_panel_keeps_each_element_together() -> None:
    """Barra y dock van en bloques: sus opciones no se mezclan entre sí."""
    contents = PANEL.read_text(encoding="utf-8")

    bar_position = contents.index("options: root.barPositionRows")
    bar_mode = contents.index("options: root.barModeRows")
    dock_position = contents.index("options: root.dockPositionRows")
    dock_mode = contents.index("options: root.dockModeRows")

    assert bar_position < bar_mode < dock_position < dock_mode


def test_the_configs_panel_offers_the_bar_mode() -> None:
    """Configs permite alternar dinámica/anclada sin tocar el JSON."""
    contents = PANEL.read_text(encoding="utf-8")

    assert "readonly property var barModeRows" in contents
    assert 'value: ShellLayout.barAnchored ? "anchored" : "dynamic"' in contents
    assert 'onPicked: (key) => ShellLayout.setBarAnchored(key === "anchored")' in contents

"""Contrato de la posición de barra y dock.

La barra y el dock sólo cambian de borde (arriba/abajo): su forma —la curva
cóncava pegada al filo—, la sombra y las animaciones se espejan, no se
rediseñan. La preferencia vive en display.json y se elige en el panel.
"""

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAYOUT = REPOSITORY_ROOT / "theme" / "ShellLayout.qml"
SHELL = REPOSITORY_ROOT / "shell.qml"
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "ShellConfigPanel.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
TRAY = REPOSITORY_ROOT / "modules" / "bar" / "Tray.qml"
TRAY_MENU = REPOSITORY_ROOT / "modules" / "bar" / "TrayMenu.qml"
DOCK = REPOSITORY_ROOT / "modules" / "dock" / "Dock.qml"
SMART_HIDE = REPOSITORY_ROOT / "modules" / "dock" / "DockSmartHide.js"


def test_the_positions_persist_in_display_json() -> None:
    contents = LAYOUT.read_text(encoding="utf-8")

    assert 'property string barPosition: "top"' in contents
    assert 'property string dockPosition: "bottom"' in contents
    assert '\\"barPosition\\":\\"' in contents
    assert '\\"dockPosition\\":\\"' in contents


def test_only_the_two_edges_are_accepted() -> None:
    """Un valor raro a mano no deja la ventana sin anclaje."""
    contents = LAYOUT.read_text(encoding="utf-8")

    assert "function setBarPosition(value)" in contents
    assert "function setDockPosition(value)" in contents
    assert 'if (value !== "top" && value !== "bottom")' in contents
    assert 'adapter.barPosition === "bottom" ? "bottom" : "top"' in contents
    assert 'adapter.dockPosition === "top" ? "top" : "bottom"' in contents


def test_the_shell_hands_the_positions_to_both_windows() -> None:
    contents = SHELL.read_text(encoding="utf-8")

    assert "position: ShellLayout.barPosition" in contents
    assert "position: ShellLayout.dockPosition" in contents


def test_the_bar_mirrors_shape_shadow_and_entry() -> None:
    contents = BAR.read_text(encoding="utf-8")

    assert 'property string position: "top"' in contents
    assert "readonly property bool atBottom: bar.position" in contents
    # Espejo del trazado sin duplicarlo: y() e inverse() voltean el path.
    assert "readonly property bool flip: bar.atBottom" in contents
    assert "function y(value) { return flip ? glass.height - value : value }" in contents
    assert "function inverse(value)" in contents
    # La sombra cae hacia dentro de la pantalla en ambos bordes.
    assert "? -Theme.shadowOffsetY : Theme.shadowOffsetY" in contents
    # La franja clicable y las barreras modales siguen el borde.
    assert "y: bar.atBottom ? parent.height - Theme.barHeight : 0" in contents
    assert "y: hitArea.y" in contents


def test_the_tray_menus_open_away_from_the_edge() -> None:
    tray = TRAY.read_text(encoding="utf-8")
    menu = TRAY_MENU.read_text(encoding="utf-8")

    assert "property bool menusAbove: false" in tray
    assert "menusAbove: bar.atBottom" in (REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml").read_text(
        encoding="utf-8"
    )
    assert "root.menusAbove ? Edges.Bottom : Edges.Top" in tray
    assert "root.menusAbove ? Edges.Top : Edges.Bottom" in tray
    assert "property bool menusAbove: false" in menu
    assert "rotation: root.menusAbove ? 180 : 0" in menu


def test_the_dock_mirrors_hide_edge_and_shape() -> None:
    contents = DOCK.read_text(encoding="utf-8")

    assert 'property string position: "bottom"' in contents
    assert "readonly property bool atTop: dock.position" in contents
    assert "top: dock.atTop" in contents
    assert "bottom: !dock.atTop" in contents
    assert "? -DockSmartHide.dockOffset(dock.smartState, dock.metrics)" in contents
    assert "readonly property bool flip: dock.atTop" in contents
    assert "? Theme.shadowOffsetY : -Theme.shadowOffsetY" in contents
    assert "position: dock.position" in contents


def test_the_hot_edge_follows_the_dock_position() -> None:
    contents = SMART_HIDE.read_text(encoding="utf-8")

    assert 'var atTop = metrics.position === "top";' in contents
    assert "y: atTop ? 0 : metrics.surfaceHeight - metrics.hotEdge" in contents
    assert "y: atTop ? 0 : metrics.shadowPad" in contents


def test_the_panel_offers_the_two_position_rows() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "readonly property var barPositionRows" in contents
    assert "readonly property var dockPositionRows" in contents
    assert "ShellLayout.setBarPosition(key)" in contents
    assert "ShellLayout.setDockPosition(key)" in contents
    assert 'text: "Posición"' in contents


def test_the_category_is_named_after_the_shell() -> None:
    rail = (REPOSITORY_ROOT / "modules" / "secondmenu" / "SecondMenu.qml").read_text(
        encoding="utf-8"
    )

    assert "Configs de Caparazón Shell" in rail
    assert "Configs de la shell" not in rail
    assert "Configs de la shell" not in PANEL.read_text(encoding="utf-8")

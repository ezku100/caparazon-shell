"""Contrato de la posición de barra y dock.

La barra y el dock cambian de borde (arriba/abajo/izquierda/derecha): su
forma —la curva cóncava pegada al filo—, la sombra y las animaciones se
espejan, no se rediseñan. La preferencia vive en display.json y se elige en
el panel.
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
MUSIC_WIDGET = REPOSITORY_ROOT / "modules" / "dock" / "MusicWidget.qml"
SMART_HIDE = REPOSITORY_ROOT / "modules" / "dock" / "DockSmartHide.js"


def test_the_positions_persist_in_display_json() -> None:
    contents = LAYOUT.read_text(encoding="utf-8")

    assert 'property string barPosition: "top"' in contents
    assert 'property string dockPosition: "bottom"' in contents
    assert '\\"barPosition\\":\\"' in contents
    assert '\\"dockPosition\\":\\"' in contents


def test_only_the_known_edges_are_accepted() -> None:
    """Un valor raro a mano no deja la ventana sin anclaje.

    La barra admite los cuatro bordes; el dock, los tres que usa. Al leer el
    archivo, cualquier cosa que no sea un borde conocido vuelve al defecto.
    """
    contents = LAYOUT.read_text(encoding="utf-8")

    assert "function setBarPosition(value)" in contents
    assert "function setDockPosition(value)" in contents
    assert 'if (value !== "top" && value !== "bottom"' in contents
    assert '&& value !== "left" && value !== "right")' in contents
    assert 'adapter.barPosition === "bottom"' in contents
    assert '|| adapter.barPosition === "left"' in contents
    assert '|| adapter.barPosition === "right"' in contents
    assert '? adapter.barPosition : "top"' in contents
    assert '["top", "left", "right"].indexOf(adapter.dockPosition) >= 0' in contents


def test_the_shell_hands_the_positions_to_both_windows() -> None:
    contents = SHELL.read_text(encoding="utf-8")

    assert "position: ShellLayout.barPosition" in contents
    assert "position: ShellLayout.dockPosition" in contents


def test_the_bar_mirrors_shape_shadow_and_entry() -> None:
    contents = BAR.read_text(encoding="utf-8")

    assert 'property string position: "top"' in contents
    assert "readonly property bool atBottom: bar.position" in contents
    assert "readonly property bool atLeft: bar.position" in contents
    assert "readonly property bool atRight: bar.position" in contents
    assert "readonly property bool vertical: bar.atLeft || bar.atRight" in contents
    # Espejo del trazado sin duplicarlo: px()/py()/inverse() voltean el path.
    assert "function px(x, y)" in contents
    assert "function py(x, y)" in contents
    assert "function inverse(value)" in contents
    assert "readonly property bool flip" not in contents
    # La sombra cae hacia dentro de la pantalla en los cuatro bordes.
    assert "shadowHorizontalOffset: bar.atLeft" in contents
    assert "(bar.atRight ? -Theme.shadowOffsetY : 0)" in contents
    assert "(bar.atBottom ? -Theme.shadowOffsetY : Theme.shadowOffsetY)" in contents
    # La franja clicable y las barreras modales siguen el borde (la máscara
    # la calcula BarSmartHide según el borde y el estado de la barra).
    assert "BarSmartHide.maskRect(bar.smartState" in contents
    assert "position: bar.position" in contents
    assert "y: hitArea.y" in contents


def test_the_tray_menus_open_away_from_the_edge() -> None:
    tray = TRAY.read_text(encoding="utf-8")
    menu = TRAY_MENU.read_text(encoding="utf-8")
    bar = BAR.read_text(encoding="utf-8")

    assert "property bool menusAbove: false" in tray
    assert "menusAbove: bar.atBottom" in bar
    assert "root.menusAbove ? Edges.Bottom : Edges.Top" in tray
    assert "root.menusAbove ? Edges.Top : Edges.Bottom" in tray
    # En vertical la bandeja abre su menú hacia el interior y sin cola.
    assert "menusAbove: true" in bar
    assert "vertical: true" in bar
    assert "barAtLeft: bar.atLeft" in bar
    assert "anchor.edges: root.vertical" in menu
    assert "root.barAtLeft" in menu
    assert "rotation: root.menusAbove ? 180 : 0" not in menu


def test_the_dock_follows_all_four_edges() -> None:
    contents = DOCK.read_text(encoding="utf-8")

    assert 'property string position: "bottom"' in contents
    for edge in ("atTop", "atBottom", "atLeft", "atRight"):
        assert f"readonly property bool {edge}: dock.position" in contents
    assert "readonly property bool vertical: dock.atLeft || dock.atRight" in contents

    # La ventana cruza la pantalla por su eje largo y sólo ocupa el grosor:
    # horizontal va arriba/abajo, vertical se pega a un lado.
    assert "top: dock.atTop || dock.vertical" in contents
    assert "bottom: dock.atBottom || dock.vertical" in contents
    assert "left: dock.atLeft || !dock.vertical" in contents
    assert "right: dock.atRight || !dock.vertical" in contents

    # El escondite sale por el borde elegido y la sombra cae hacia dentro.
    assert "DockSmartHide.dockOffset(dock.smartState, dock.metrics)" in contents
    assert "? -hideOffset" in contents
    assert "shadowHorizontalOffset: dock.atLeft" in contents
    assert "position: dock.position" in contents


def test_the_vertical_dock_builds_its_length_from_the_column() -> None:
    """En columna el largo sale de la columna, no de la fila."""
    contents = DOCK.read_text(encoding="utf-8")

    assert "id: dockColumn" in contents
    assert "visible: dock.vertical" in contents
    assert "visible: !dock.vertical" in contents
    assert "? dockColumn.implicitHeight" in contents
    assert "dockColumn.width - width" in contents


def test_the_vertical_dock_keeps_the_glass_behind_the_content() -> None:
    """El cristal se dibuja aparte y el contenido no se gira con él.

    El trazado se lleva al borde mapeando sus puntos (`px`/`py`), así que el
    contenido no puede vivir dentro del `Shape`: quedaría torcido.
    """
    contents = DOCK.read_text(encoding="utf-8")

    assert "function px(x, y)" in contents
    assert "function py(x, y)" in contents
    assert "readonly property bool flip" not in contents
    # Un solo trazado sirve para los cuatro bordes.
    assert contents.count("ShapePath {") == 1
    assert "rotation:" not in contents


def test_the_compact_music_tile_keeps_only_the_cover() -> None:
    contents = (REPOSITORY_ROOT / "modules" / "dock" / "MusicWidget.qml").read_text(
        encoding="utf-8"
    )

    assert "property bool compact: false" in contents
    assert "implicitWidth: compact ? 44" in contents
    assert contents.count("visible: !root.compact") == 2


def test_the_compact_tile_opens_the_music_category() -> None:
    """En columna el clic cubre la carátula entera.

    Sin la fila de controles (`controls.x` vale 0) el área de "abrir Música"
    se quedaba en 3 px: la carátula no abría nada.
    """
    contents = (REPOSITORY_ROOT / "modules" / "dock" / "MusicWidget.qml").read_text(
        encoding="utf-8"
    )

    assert "height: root.compact ? root.cardHeight : root.height" in contents
    assert "? root.width" in contents
    # En columna la tarjeta es sólo la carátula: no reserva sitio de más.
    assert "implicitHeight: root.cardHeight" in contents
    assert "compactControlsHeight" not in contents


def test_the_vertical_buttons_expand_inside_the_card() -> None:
    """En columna la tarjeta se estira al pasar el ratón y vuelve al salir.

    Los controles van dentro de la propia tarjeta (no flotan encima de los
    iconos) y el cristal crece hacia abajo sin mover su borde superior, para
    que el puntero no pierda la carátula y el despliegue no parpadee.
    """
    contents = DOCK.read_text(encoding="utf-8")
    widget = MUSIC_WIDGET.read_text(encoding="utf-8")

    # El despliegue lo decide el hover de la propia tarjeta, sin temporizador.
    assert "readonly property bool musicExpanded: dock.vertical && musicTile.hovering" in contents
    assert "expanded: dock.musicExpanded" in contents
    assert "musicDeployOpen" not in contents

    # El cristal se calcula con el largo plegado y sigue al contenido animado.
    assert "readonly property int restContent: dock.vertical" in contents
    assert "readonly property int collapsedLength: Math.max(308," in contents
    assert "dock.deployAnimating" in contents
    assert "parent.height\n                - (dock.collapsedLength + 2 * Theme.shadowPad)) / 2" in contents

    # La tarjeta lleva sus tres botones dentro y se pliega con la altura.
    assert "property bool expanded: false" in widget
    assert "readonly property int buttonsHeight: 76" in widget
    assert "Behavior on height {" in widget
    # Tres en la fila horizontal y los mismos tres apilados en la columna.
    assert widget.count("MusicButton {") == 6
    assert contents.count("MusicButton {") == 0


def test_the_hot_edge_follows_the_dock_position() -> None:
    contents = SMART_HIDE.read_text(encoding="utf-8")

    assert "function edges(metrics)" in contents
    assert "var e = edges(metrics)" in contents
    # Oculto deja sólo una franja fina en el borde; revelado, el cuerpo entero.
    assert "x: e.left ? 0 : metrics.surfaceWidth - hot" in contents
    assert "y: e.top ? 0 : metrics.surfaceHeight - hot" in contents
    assert "x: e.left ? 0 : metrics.surfaceWidth - thickness" in contents
    assert "y: e.top ? 0 : metrics.shadowPad" in contents


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

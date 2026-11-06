"""Contrato del dock inteligente (auto-oculto con modo anclado en configs).

El QML no se puede ejecutar en un test, así que aquí se comprueba el
cableado: que el dock lea el modo de su configuración, que el interruptor
viva en Configs de la shell (sin botón de pin en el dock), que se quede
quieto con un menú abierto y que los estados sigan saliendo de la librería.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DOCK = REPOSITORY_ROOT / "modules" / "dock" / "Dock.qml"
THEME = REPOSITORY_ROOT / "theme" / "Theme.qml"
README = REPOSITORY_ROOT / "README.md"


def test_the_theme_declares_the_auto_hide_tokens() -> None:
    """La franja sensible y la gracia de ocultado salen del tema."""
    contents = THEME.read_text(encoding="utf-8")

    assert "property int dockHotEdge: 6" in contents
    assert "property int dockHideGrace: 600" in contents


def test_the_dock_reads_the_pin_from_its_config() -> None:
    """El pin vive en dock.json y se llama dockPinned."""
    contents = DOCK.read_text(encoding="utf-8")

    assert "property bool dockPinned: false" in contents
    assert (
        "readonly property bool dockPinned: pinsAdapter.dockPinned === true"
    ) in contents


def test_the_dock_toggles_the_pin_and_saves_it() -> None:
    """El dock ya no alterna el pin: el interruptor vive en configs."""
    contents = DOCK.read_text(encoding="utf-8")

    assert "togglePin" not in contents
    assert "dockPinned = !dockPinned" not in contents


def test_the_dock_shows_a_pin_button() -> None:
    """El dock no pinta ningún botón de pin."""
    contents = DOCK.read_text(encoding="utf-8")

    assert "window-pin" not in contents
    assert "window-unpin" not in contents
    assert "pinButton" not in contents


def test_the_dock_stays_while_a_menu_is_open() -> None:
    """Con un menú abierto el dock no se esconde."""
    contents = DOCK.read_text(encoding="utf-8")

    assert "menuOpen" in contents
    assert "onTriggered: if (!dock.menuOpen) dock.pointerOnDock = false" in contents
    assert "onMenuOpenChanged" in contents


def test_the_hover_detector_is_not_blocked_by_the_app_icons() -> None:
    """El detector de hover vive en la raíz de la ventana.

    Los MouseArea de los iconos de apps y de los botones multimedia se
    quedan con el hover: un handler hermano de hitArea lo perdería y el
    dock se escondería en pleno uso.
    """
    contents = DOCK.read_text(encoding="utf-8")

    hit_block = contents.split("id: hitArea", 1)[1].split("\n    }", 1)[0]
    assert "HoverHandler" not in hit_block
    assert contents.count("HoverHandler") == 1


def test_the_dock_uses_the_anchored_state() -> None:
    """Los estados vienen de la librería, con el pin como entrada."""
    contents = DOCK.read_text(encoding="utf-8")

    assert "DockSmartHide.stateFor(dock.dockPinned, dock.pointerOnDock)" in contents
    assert "DockSmartHide.exclusiveZone(dock.dockPinned, dock.metrics)" in contents


def test_the_readme_documents_the_auto_hide_and_the_anchor() -> None:
    """El README explica el auto-ocultado y el modo anclado desde configs."""
    contents = README.read_text(encoding="utf-8").lower()

    assert "oculto" in contents
    assert "anclado" in contents
    assert "configs de la shell" in contents

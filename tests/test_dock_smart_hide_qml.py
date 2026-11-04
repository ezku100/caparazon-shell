"""Contrato del dock inteligente (auto-oculto siempre con pin).

El QML no se puede ejecutar en un test, así que aquí se comprueba el
cableado: que el dock lea el pin de su configuración, que lo guarde al
tocar el botón, que se quede quieto con un menú abierto y que los estados
sigan saliendo de la librería.
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
    """Un clic en el botón alterna el pin y lo guarda en disco."""
    contents = DOCK.read_text(encoding="utf-8")

    assert "pinsAdapter.dockPinned = !pinsAdapter.dockPinned" in contents
    assert "pinsFile.writeAdapter()" in contents


def test_the_dock_shows_a_pin_button() -> None:
    """El botón de pin vive dentro del dock y su icono es discreto."""
    contents = DOCK.read_text(encoding="utf-8")

    assert "IconResolver.source(" in contents
    assert 'dock.dockPinned ? "window-unpin" : "window-pin"' in contents
    assert "implicitSize: 22" in contents
    assert "togglePin" in contents


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


def test_the_readme_documents_the_auto_hide_and_the_pin() -> None:
    """El README explica el auto-ocultado y el pin."""
    contents = README.read_text(encoding="utf-8").lower()

    assert "oculto" in contents
    assert "pin" in contents

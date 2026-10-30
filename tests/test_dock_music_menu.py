"""Contrato del cableado del menú de música en el dock.

Al hacer clic sobre el widget de música del dock, este emite activated y el
dock abre el menú secundario directamente en la categoría Música.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

SHELL = REPOSITORY_ROOT / "shell.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
DOCK = REPOSITORY_ROOT / "modules" / "dock" / "Dock.qml"
MUSIC_WIDGET = REPOSITORY_ROOT / "modules" / "dock" / "MusicWidget.qml"


def contents(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_music_widget_emits_activated_signal() -> None:
    """El widget de música expone la señal activated para avisar de un clic."""
    assert "signal activated()" in contents(MUSIC_WIDGET)


def test_music_widget_has_click_mouse_area() -> None:
    """El widget de música usa un MouseArea para detectar el clic en la tarjeta."""
    contents_widget = contents(MUSIC_WIDGET)
    assert "MouseArea" in contents_widget
    assert "onClicked: root.activated()" in contents_widget


def test_dock_has_second_menu_state_property() -> None:
    """El dock expone property var secondMenuState para recibir el estado global."""
    assert "property var secondMenuState: null" in contents(DOCK)


def test_dock_has_open_music_menu_function() -> None:
    """El dock ofrece la función openMusicMenu() que pasa la categoría 'musica'."""
    contents_dock = contents(DOCK)
    assert "function openMusicMenu()" in contents_dock
    assert 'secondMenuState.open(dock.screen, "musica")' in contents_dock


def test_dock_connects_music_widget_activated() -> None:
    """El dock conecta MusicWidget.onActivated a openMusicMenu()."""
    contents_dock = contents(DOCK)
    assert "onActivated: dock.openMusicMenu()" in contents_dock


def test_shell_passes_second_menu_state_to_dock() -> None:
    """La shell entrega secondMenuState al delegate del Dock."""
    contents_shell = contents(SHELL)
    assert "secondMenuState: shellRoot.secondMenuState" in contents_shell


def test_second_menu_open_accepts_category_parameter() -> None:
    """open() en secondMenuState acepta una categoría opcional."""
    contents_shell = contents(SHELL)
    assert "function open(screen, wantedCategory)" in contents_shell
    assert "category = wantedCategory" in contents_shell


def test_bar_clock_opens_second_menu_with_calendar_category() -> None:
    """El reloj de la barra abre el menú secundario forzando 'calendario'."""
    assert 'secondMenuState.open(bar.screen, "calendario")' in contents(BAR)

"""Contrato del cableado del menú secundario (calendario).

El menú secundario se abre desde el reloj de la barra y es independiente
del menú de aplicaciones. Aquí se comprueba el cableado sin levantar la
shell: señales, estado global, IPC y Loader.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

CLOCK = REPOSITORY_ROOT / "modules" / "bar" / "Clock.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
SHELL = REPOSITORY_ROOT / "shell.qml"


def contents(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_clock_emits_activated_signal() -> None:
    """El reloj emite activated para que la barra abra el menú."""
    assert "signal activated()" in contents(CLOCK)


def test_clock_has_mouse_area() -> None:
    """El reloj es clicable mediante un MouseArea."""
    assert "MouseArea" in contents(CLOCK)


def test_bar_has_open_second_menu() -> None:
    """La barra expone openSecondMenu()."""
    assert "openSecondMenu" in contents(BAR)


def test_bar_has_second_menu_loader() -> None:
    """La barra carga SecondMenu en un Loader."""
    assert "SecondMenu" in contents(BAR)


def test_shell_has_second_menu_state() -> None:
    """La shell mantiene el estado global del menú secundario."""
    assert "secondMenuState" in contents(SHELL)


def test_shell_has_menu2_ipc() -> None:
    """Existe un IPC menu2 para atajos de KDE."""
    assert 'target: "menu2"' in contents(SHELL)


def test_app_menu_opening_closes_second_menu() -> None:
    """Abrir el menú de apps cierra el secundario."""
    contents_shell = contents(SHELL)
    assert "secondMenuState.close()" in contents_shell


def test_second_menu_opening_closes_app_menu() -> None:
    """Abrir el menú secundario cierra el de apps."""
    contents_shell = contents(SHELL)
    assert "appMenuState.close()" in contents_shell


def test_shell_keeps_a_notification_history() -> None:
    """La shell guarda un historial porque el servidor sólo retiene la última."""
    assert "notificationHistoryModel" in contents(SHELL)


def test_bar_passes_the_notification_history() -> None:
    """La barra entrega el historial al menú secundario."""
    assert "notificationHistory" in contents(BAR)

"""Contrato del cableado del menú secundario (calendario).

El menú secundario se abre desde el reloj de la barra y es independiente
del menú de aplicaciones. Aquí se comprueba el cableado sin levantar la
shell: señales, estado global, IPC y Loader.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

CLOCK = REPOSITORY_ROOT / "modules" / "bar" / "Clock.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
SHELL = REPOSITORY_ROOT / "shell.qml"
SECOND_MENU_DIR = REPOSITORY_ROOT / "modules" / "secondmenu"
SECOND_MENU = SECOND_MENU_DIR / "SecondMenu.qml"
CALENDAR_PANEL = SECOND_MENU_DIR / "CalendarPanel.qml"
NOTIFICATION_HISTORY = SECOND_MENU_DIR / "NotificationHistory.qml"
OPEN_APP = SECOND_MENU_DIR / "openapp.sh"


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


def test_history_keeps_the_desktop_entry() -> None:
    """Cada entrada guarda su .desktop para poder abrir la app al pulsarla."""
    assert "desktopEntry: String(notification.desktopEntry" in contents(SHELL)


def test_history_can_be_cleared() -> None:
    """El historial ofrece un botón Limpiar que vacía el modelo."""
    contents_history = contents(NOTIFICATION_HISTORY)
    assert "Limpiar" in contents_history
    assert "root.model.clear()" in contents_history


def test_history_row_activates_its_app() -> None:
    """Pulsar una notificación avisa al menú para abrir la app de origen."""
    assert "signal notificationActivated" in contents(NOTIFICATION_HISTORY)
    assert "onNotificationActivated" in contents(CALENDAR_PANEL)
    assert "openNotificationApp" in contents(SECOND_MENU)


def test_second_menu_category_uses_the_bell_icon() -> None:
    """La categoría del rail se identifica con el icono de notificaciones."""
    assert 'icon: "notifications"' in contents(SECOND_MENU)


def test_header_shows_the_current_temperature() -> None:
    """La temperatura actual se muestra junto al reloj."""
    assert "Math.round(weather.temperature)" in contents(CALENDAR_PANEL)


def test_openapp_script_is_executable() -> None:
    """openapp.sh se invoca desde QML, así que necesita permiso de ejecución."""
    assert os.access(OPEN_APP, os.X_OK)


def test_openapp_script_rejects_paths() -> None:
    """El id llega de una notificación, así que no puede traer rutas."""
    result = subprocess.run(  # noqa: S603
        [str(OPEN_APP), "../../etc/passwd"],
        capture_output=True,
        check=False,
        text=True,
        timeout=10,
    )
    assert result.returncode == 2

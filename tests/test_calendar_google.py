"""Contrato del calendario de Google en la categoría Calendario."""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SERVICE = REPOSITORY_ROOT / "modules" / "secondmenu" / "CalendarService.qml"
SETTINGS = REPOSITORY_ROOT / "modules" / "secondmenu" / "PanelSettings.qml"
DAY_EVENTS = REPOSITORY_ROOT / "modules" / "secondmenu" / "DayEvents.qml"
DIALOG = REPOSITORY_ROOT / "modules" / "secondmenu" / "CalendarLinkDialog.qml"
CALENDAR_PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "CalendarPanel.qml"
SECOND_MENU = REPOSITORY_ROOT / "modules" / "secondmenu" / "SecondMenu.qml"
INSTALL = REPOSITORY_ROOT / "install.sh"


def contents(path: Path) -> str:
    """Devuelve el contenido de un archivo del repositorio."""
    return path.read_text(encoding="utf-8")


def test_the_service_invokes_the_script_with_its_range() -> None:
    """El servicio llama a gcal.py events con --from y --to."""
    service = contents(SERVICE)
    assert "gcal.py" in service
    assert '"events"' in service
    assert '"--from"' in service
    assert '"--to"' in service


def test_the_service_parses_stdout_with_a_collector() -> None:
    """Sigue el molde de WeatherService: Process + StdioCollector."""
    service = contents(SERVICE)
    assert "StdioCollector" in service
    assert "JSON.parse" in service


def test_the_service_exposes_the_contract() -> None:
    """Las propiedades y funciones que consumen el panel y el diálogo."""
    service = contents(SERVICE)
    for name in (
        "property var calendars",
        "property var byDay",
        "property bool linked",
        "property bool stale",
        "function refresh",
        "function setRange",
        "function eventsForDay",
        "function calendarIds",
    ):
        assert name in service


def test_the_view_is_remembered_in_the_cache() -> None:
    """La preferencia vive en la caché de Caparazón, como la de Música."""
    settings = contents(SETTINGS)
    assert ".cache/caparazon" in settings
    assert "secondmenu.json" in settings
    assert "property string view" in settings
    assert "notifications" in settings
    assert '"events"' in settings


def test_the_setting_is_written_atomically() -> None:
    """Se escribe a un .tmp y se renombra, sin dejar el JSON a medias."""
    settings = contents(SETTINGS)
    assert ".tmp" in settings
    assert "mv " in settings


def test_only_the_two_views_are_accepted() -> None:
    """Nada más que notificaciones o eventos puede guardarse."""
    settings = contents(SETTINGS)
    assert 'value !== "events" && value !== "notifications"' in settings


def test_the_day_list_shows_hour_calendar_and_title() -> None:
    """Cada fila lleva hora, nombre del calendario y título."""
    panel = contents(DAY_EVENTS)
    assert "property var events" in panel
    assert "calendar_name" in panel
    assert "all_day" in panel
    assert "Todo el día" in panel


def test_the_day_list_has_an_empty_state() -> None:
    """Un día sin eventos no deja la columna en blanco."""
    assert "Sin eventos este día" in contents(DAY_EVENTS)


def test_the_day_list_uses_the_calendar_colour() -> None:
    """El punto de la fila toma el color del evento."""
    panel = contents(DAY_EVENTS)
    assert "color" in panel
    assert "radius: 4" in panel


def test_the_dialog_pastes_and_saves_the_url() -> None:
    """El diálogo usa TextInput, wl-paste y gcal.py set-url."""
    dialog = contents(DIALOG)
    assert "TextInput" in dialog
    assert "wl-paste" in dialog
    assert '"set-url"' in dialog
    assert "xdg-open" in dialog


def test_the_dialog_manages_linked_calendars() -> None:
    """Se pueden quitar, activar, renombrar y recolorear."""
    dialog = contents(DIALOG)
    for command in ('"remove"', '"set-enabled"', '"set-name"', '"set-color"'):
        assert command in dialog


def test_the_dialog_never_shows_the_full_url() -> None:
    """De la credencial sólo se muestran los últimos caracteres."""
    dialog = contents(DIALOG)
    assert "ical_tail" in dialog
    assert "ical_url" not in dialog


def test_the_dialog_shows_the_message_of_the_script() -> None:
    """El error que devuelve gcal.py se muestra tal cual."""
    dialog = contents(DIALOG)
    assert "data.error" in dialog
    assert "root.statusText" in dialog


def test_the_column_switches_between_history_and_events() -> None:
    """Las flechitas cambian la vista y la etiqueta lo dice."""
    panel = contents(CALENDAR_PANEL)
    assert "PanelSettings" in panel
    assert "NotificationHistory" in panel
    assert "DayEvents" in panel
    assert '"Eventos"' in panel
    assert '"Notificaciones"' in panel


def test_the_view_is_remembered_and_not_written_by_hand() -> None:
    """El panel delega en PanelSettings la memoria de la vista."""
    panel = contents(CALENDAR_PANEL)
    assert "settings.setView(value)" in panel
    assert "onLoadedChanged" in panel
    assert "root.view = settings.view" in panel


def test_the_grid_selects_a_day() -> None:
    """Clic en una celda selecciona el día, con marca distinta de hoy."""
    panel = contents(CALENDAR_PANEL)
    assert "selectDay" in panel
    assert "selectedDay" in panel
    assert "border.color: Theme.m3Primary" in panel


def test_the_grid_draws_colour_dots() -> None:
    """Los días con eventos llevan puntos de color, con tope de tres."""
    panel = contents(CALENDAR_PANEL)
    assert "colorsForDay" in panel
    assert "length > 3" in panel


def test_the_google_badge_opens_the_dialog() -> None:
    """El badge G vive en la fila del mes y abre el diálogo."""
    panel = contents(CALENDAR_PANEL)
    assert "CalendarLinkDialog" in panel
    assert "overlayChanged" in panel
    assert 'text: "G"' in panel


def test_the_panel_asks_the_service_for_the_visible_month() -> None:
    """El rango que se pide cubre el mes visible y sus vecinos."""
    panel = contents(CALENDAR_PANEL)
    assert "updateRange" in panel
    assert "calendar.setRange" in panel


def test_escape_closes_the_dialog_before_the_menu() -> None:
    """Con el overlay abierto, Escape cierra el diálogo y no el menú."""
    menu = contents(SECOND_MENU)
    assert "overlayOpen" in menu
    assert "enabled: root.active && !root.overlayOpen" in menu
    assert "onOverlayChanged: (open) => root.overlayOpen = open" in menu
    assert 'sequence: "Escape"' in contents(DIALOG)


def test_the_installer_requires_dateutil() -> None:
    """Sin python3-dateutil las recurrencias no se expanden."""
    installer = contents(INSTALL)
    assert "python3-dateutil" in installer
    assert "require_calendar_dependencies" in installer

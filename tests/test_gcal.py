"""Contrato del script de calendario: ICS, recurrencias y configuración."""

from __future__ import annotations

import contextlib
import http.server
import json
import subprocess
import sys
import threading
from datetime import date
from pathlib import Path
from typing import TYPE_CHECKING, cast

import pytest

if TYPE_CHECKING:
    from collections.abc import Generator

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
FIXTURE = REPOSITORY_ROOT / "tests" / "support" / "calendario-ejemplo.ics"
GCAL = REPOSITORY_ROOT / "modules" / "secondmenu" / "gcal.py"

from modules.secondmenu import gcal  # noqa: E402


@contextlib.contextmanager
def _local_ics_server(body: str, content_type: str = "text/calendar") -> Generator[str]:
    """Levanta un servidor local que sirve un cuerpo fijo."""

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            payload = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            _ = self.wfile.write(payload)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        host, port = server.server_address[:2]
        yield f"http://{host}:{port}/basic.ics"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def _run_cli(*arguments: str) -> subprocess.CompletedProcess[str]:
    """Ejecuta el script y devuelve el resultado."""
    return subprocess.run(  # noqa: S603
        [sys.executable, str(GCAL), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )


def fixture_text() -> str:
    """Devuelve el ICS de ejemplo."""
    return FIXTURE.read_text(encoding="utf-8")


def test_parse_ics_reads_the_events() -> None:
    """El ICS de ejemplo tiene cinco eventos base."""
    events = gcal.parse_ics(fixture_text())
    assert len(events) == 5
    assert {event.summary for event in events} == {
        "Daily sync",
        "Feriado",
        "Semanal",
        "Segundo martes",
        "Madrugada",
    }


def test_the_all_day_event_keeps_its_date() -> None:
    """Un evento VALUE=DATE no se convierte de zona."""
    events = gcal.parse_ics(fixture_text())
    feriado = next(event for event in events if event.summary == "Feriado")
    assert feriado.all_day is True
    assert feriado.start.date() == date(2026, 11, 4)


def test_a_weekly_rule_expands_on_its_weekdays() -> None:
    """El semanal cae lunes y miércoles dentro del rango pedido."""
    events = gcal.expand_events(
        gcal.parse_ics(fixture_text()), date(2026, 11, 2), date(2026, 11, 8)
    )
    days = sorted(
        event.start.date() for event in events if event.summary == "Semanal"
    )
    assert days == [date(2026, 11, 2), date(2026, 11, 4)]


def test_a_monthly_rule_skips_excluded_dates() -> None:
    """El mensual cae el segundo martes y respeta el EXDATE."""
    base = gcal.parse_ics(fixture_text())
    days = sorted(
        event.start.date()
        for event in gcal.expand_events(base, date(2026, 10, 1), date(2026, 12, 31))
        if event.summary == "Segundo martes"
    )
    assert days == [date(2026, 10, 13), date(2026, 12, 8)]
    assert not [
        event
        for event in gcal.expand_events(base, date(2026, 11, 1), date(2026, 11, 30))
        if event.summary == "Segundo martes"
    ]


def test_an_event_crossing_midnight_lands_on_both_days() -> None:
    """El evento de 23:00 a 01:00 aparece en los dos días."""
    events = gcal.expand_events(
        gcal.parse_ics(fixture_text()), date(2026, 11, 1), date(2026, 11, 30)
    )
    by_day = gcal.group_by_day(events)
    assert "Madrugada" in [event.summary for event in by_day["2026-11-05"]]
    assert "Madrugada" in [event.summary for event in by_day["2026-11-06"]]


def test_saving_a_config_sets_owner_only_permissions(tmp_path: Path) -> None:
    """La configuración es una credencial: sólo el dueño la lee."""
    path = tmp_path / "calendar.json"
    calendar = gcal.Calendar(
        id="trabajo",
        name="Trabajo",
        color="#4285F4",
        enabled=True,
        ical_url="https://example.invalid/a.ics",
    )
    gcal.save_config([calendar], path=path)
    assert path.stat().st_mode & 0o777 == 0o600


def test_a_missing_or_corrupt_config_is_empty(tmp_path: Path) -> None:
    """Sin archivo o con JSON roto, la shell ve cero calendarios."""
    missing = tmp_path / "nope.json"
    assert gcal.load_config(path=missing) == []

    broken = tmp_path / "broken.json"
    _ = broken.write_text("{no es json", encoding="utf-8")
    assert gcal.load_config(path=broken) == []
    assert broken.exists()


def test_the_url_never_leaves_the_script() -> None:
    """calendar_to_json no incluye la URL, sólo una pista de su final."""
    calendar = gcal.Calendar(
        id="casa",
        name="Casa",
        color="#34A853",
        enabled=True,
        ical_url="https://calendar.google.com/ical/SECRETO1234/basic.ics",
    )
    payload = gcal.calendar_to_json(calendar)
    assert "ical_url" not in payload
    assert payload["ical_tail"] == "1234"
    assert "SECRETO1234" not in str(payload)


def test_the_tail_hint_tells_google_calendars_apart() -> None:
    """La pista final distingue calendarios y no se queda en 'public'."""
    base = "https://calendar.google.com/calendar/ical/abc123%40group.calendar.google.com"
    urls = [
        base + "/private-9f8e7d6c5b4a/basic.ics",
        base + "/public/basic.ics",
        "http://127.0.0.1:8777/calendario-ejemplo.ics",
    ]
    pistas = {
        str(
            gcal.calendar_to_json(
                gcal.Calendar(
                    id=f"cal-{indice}",
                    name="Prueba",
                    color="#4285F4",
                    enabled=True,
                    ical_url=url,
                ),
            )["ical_tail"],
        )
        for indice, url in enumerate(urls)
    }
    assert pistas == {"5b4a", "c123", "mplo"}
    assert "blic" not in pistas


def test_a_saved_config_round_trips(tmp_path: Path) -> None:
    """Lo que se guarda se vuelve a leer igual."""
    path = tmp_path / "calendar.json"
    calendar = gcal.Calendar(
        id="casa",
        name="Casa",
        color="#34A853",
        enabled=True,
        ical_url="https://example.invalid/SECRETO/basic.ics",
    )
    gcal.save_config([calendar], path=path)
    assert gcal.load_config(path=path) == [calendar]


def test_identifiers_are_readable_and_unique() -> None:
    """El identificador sale del nombre y no se repite."""
    existing = [
        gcal.Calendar(
            id="trabajo",
            name="Trabajo",
            color="#4285F4",
            enabled=True,
            ical_url="https://example.invalid/a.ics",
        )
    ]
    assert gcal.slugify("Año Nuevo") == "ano-nuevo"
    assert gcal.unique_id("Trabajo", existing) == "trabajo-2"
    assert gcal.unique_id("Casa", existing) == "casa"


def test_fetch_ics_reads_a_local_server() -> None:
    """La descarga lee el cuerpo del servidor."""
    with _local_ics_server(fixture_text()) as url:
        assert "BEGIN:VCALENDAR" in gcal.fetch_ics(url)


def test_validate_url_rejects_a_page_that_is_not_a_calendar() -> None:
    """Una página que no es iCal no se puede vincular."""
    with (
        _local_ics_server("<html>no es un calendario</html>", "text/html") as url,
        pytest.raises(gcal.CalendarError),
    ):
        _ = gcal.validate_url(url)


def test_the_cache_is_reused_and_expires(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Con caché fresca no se descarga; pasada la TTL sí."""
    monkeypatch.setenv("HOME", str(tmp_path))
    gcal.write_cached_ics("trabajo", "BEGIN:VCALENDAR")
    assert gcal.read_cached_ics("trabajo", max_age=900) == "BEGIN:VCALENDAR"
    assert gcal.read_cached_ics("trabajo", max_age=0) is None


def test_a_failing_feed_falls_back_to_stale_cache(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Si el feed falla, se sirve la caché y se marca stale."""
    monkeypatch.setenv("HOME", str(tmp_path))
    gcal.write_cached_ics("trabajo", fixture_text())
    calendar = gcal.Calendar(
        id="trabajo",
        name="Trabajo",
        color="#4285F4",
        enabled=True,
        ical_url="https://example.invalid/feed.ics",
    )

    message = "no se pudo descargar el calendario"

    def broken_fetch(_url: str, _timeout: float = 10.0) -> str:
        raise gcal.CalendarError(message)

    payload = gcal.build_payload(
        [calendar],
        date(2026, 11, 1),
        date(2026, 11, 30),
        fetcher=broken_fetch,
        cache_max_age=0,
    )
    assert payload["stale"] is True
    by_day = cast("dict[str, list[dict[str, object]]]", payload["by_day"])
    assert by_day
    assert "2026-11-03" in by_day


def test_the_cli_events_command_prints_json(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """`events` imprime el JSON normalizado y no filtra la URL."""
    monkeypatch.setenv("HOME", str(tmp_path))
    config = tmp_path / "calendar.json"
    cache = tmp_path / "cache"
    calendar = gcal.Calendar(
        id="trabajo",
        name="Trabajo",
        color="#4285F4",
        enabled=True,
        ical_url="https://example.invalid/SECRETO/basic.ics",
    )
    gcal.save_config([calendar], path=config)
    gcal.write_cached_ics("trabajo", fixture_text(), cache_path=cache)

    result = _run_cli(
        "--config",
        str(config),
        "--cache-dir",
        str(cache),
        "events",
        "--from",
        "2026-11-01",
        "--to",
        "2026-11-30",
    )
    assert result.returncode == 0
    payload = cast("dict[str, object]", json.loads(result.stdout))
    assert payload["ok"] is True
    assert "SECRETO" not in result.stdout


def test_the_cli_links_a_calendar_from_a_local_server(tmp_path: Path) -> None:
    """`set-url` valida la dirección y guarda el calendario."""
    config = tmp_path / "calendar.json"
    with _local_ics_server(fixture_text()) as url:
        result = _run_cli(
            "--config",
            str(config),
            "set-url",
            url,
            "--name",
            "Trabajo",
            "--color",
            "#4285F4",
        )
    assert result.returncode == 0
    stored = gcal.load_config(path=config)
    assert len(stored) == 1
    assert stored[0].name == "Trabajo"
    assert stored[0].color == "#4285F4"
    assert stored[0].ical_url == url


def test_the_cli_manages_linked_calendars(tmp_path: Path) -> None:
    """Renombrar, recolorear, desactivar y quitar funcionan."""
    config = tmp_path / "calendar.json"
    gcal.save_config(
        [
            gcal.Calendar(
                id="trabajo",
                name="Trabajo",
                color="#4285F4",
                enabled=True,
                ical_url="https://example.invalid/basic.ics",
            )
        ],
        path=config,
    )
    assert _run_cli(
        "--config", str(config), "set-name", "trabajo", "Oficina"
    ).returncode == 0
    assert _run_cli(
        "--config", str(config), "set-color", "trabajo", "#34A853"
    ).returncode == 0
    assert (
        _run_cli("--config", str(config), "set-enabled", "trabajo", "false").returncode
        == 0
    )
    stored = gcal.load_config(path=config)
    assert stored[0].name == "Oficina"
    assert stored[0].color == "#34A853"
    assert stored[0].enabled is False
    assert _run_cli("--config", str(config), "remove", "trabajo").returncode == 0
    assert gcal.load_config(path=config) == []


def test_the_cli_reports_a_bad_url_without_repeating_it(tmp_path: Path) -> None:
    """El error no incluye la dirección pegada."""
    config = tmp_path / "calendar.json"
    result = _run_cli("--config", str(config), "set-url", "https://example.invalid/x")
    assert result.returncode == 1
    assert "example.invalid" not in result.stdout

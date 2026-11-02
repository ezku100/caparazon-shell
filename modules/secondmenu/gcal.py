"""Integración con calendarios iCal (Google Calendar) para Caparazón.

Este módulo es el único dueño de la credencial: guarda las URL secretas con
permisos 600, descarga el ICS con caché y publica un JSON normalizado que
`CalendarService.qml` consume.

La primera tanda de responsabilidades es el ciclo de vida de los eventos:
interpretar el ICS, expandir las recurrencias y agrupar por día.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from dataclasses import dataclass, replace
from datetime import UTC, date, datetime, time, timedelta, tzinfo
from pathlib import Path
from typing import TYPE_CHECKING, cast
from urllib.error import URLError
from urllib.parse import unquote, urlparse, urlsplit
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

if TYPE_CHECKING:
    from collections.abc import Callable
    from http.client import HTTPResponse

__all__ = [
    "PALETTE",
    "Calendar",
    "CalendarError",
    "Event",
    "build_payload",
    "cache_dir",
    "calendar_to_json",
    "config_path",
    "event_to_json",
    "expand_events",
    "fetch_ics",
    "group_by_day",
    "load_config",
    "main",
    "parse_ics",
    "read_cached_ics",
    "save_config",
    "slugify",
    "unique_id",
    "validate_url",
    "write_cached_ics",
]

PALETTE = (
    "#4285F4",
    "#EA4335",
    "#FBBC05",
    "#34A853",
    "#A142F4",
    "#24C1E0",
    "#FF6D01",
    "#E91E63",
)


class CalendarError(Exception):
    """Error de calendario con un mensaje apto para mostrar en la interfaz."""


@dataclass(frozen=True, slots=True)
class Calendar:
    """Un calendario vinculado por su URL secreta de iCal."""

    id: str
    name: str
    color: str
    enabled: bool
    ical_url: str


def config_path() -> Path:
    """Devuelve la ruta del archivo de configuración de calendarios."""
    return Path.home() / ".config" / "caparazon" / "calendar.json"


def cache_dir() -> Path:
    """Devuelve el directorio de caché de calendarios."""
    return Path.home() / ".cache" / "caparazon" / "calendar"


def slugify(name: str) -> str:
    """Convierte un nombre en un identificador corto y legible."""
    normalized = unicodedata.normalize("NFKD", name)
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_only.lower()).strip("-")
    return slug or "calendario"


def unique_id(name: str, existing: list[Calendar]) -> str:
    """Devuelve un identificador libre para un calendario nuevo."""
    base = slugify(name)
    taken = {calendar.id for calendar in existing}
    if base not in taken:
        return base
    suffix = 2
    while f"{base}-{suffix}" in taken:
        suffix += 1
    return f"{base}-{suffix}"


_GENERIC_SEGMENTS = frozenset(
    {
        "basic",
        "cal",
        "calendar",
        "feed",
        "ical",
        "ics",
        "owa",
        "private",
        "public",
    },
)


def _ical_tail(url: str) -> str:
    """Devuelve una pista no sensible del final de la URL secreta."""
    segments: list[str] = []
    for segment in urlsplit(url).path.split("/"):
        if not segment:
            continue
        limpio = unquote(segment)
        if limpio.lower().endswith(".ics"):
            limpio = limpio[: -len(".ics")]
        if limpio.lower() in _GENERIC_SEGMENTS:
            continue
        segments.append(limpio)
    if not segments:
        return ""
    candidate = segments[-1]
    if candidate.lower().startswith("private-"):
        candidate = candidate.split("-", 1)[1]
    if "@" in candidate:
        candidate = candidate.split("@", 1)[0]
    return candidate[-4:]


def calendar_to_json(calendar: Calendar) -> dict[str, str | bool]:
    """Resume un calendario sin filtrar su URL secreta."""
    return {
        "id": calendar.id,
        "name": calendar.name,
        "color": calendar.color,
        "enabled": calendar.enabled,
        "ical_tail": _ical_tail(calendar.ical_url),
    }


def _config_entry(calendar: Calendar) -> dict[str, str | bool]:
    """Construye la entrada completa del archivo de configuración."""
    return {
        "id": calendar.id,
        "name": calendar.name,
        "color": calendar.color,
        "enabled": calendar.enabled,
        "ical_url": calendar.ical_url,
    }


def _calendar_from_entry(entry: dict[str, object]) -> Calendar | None:
    """Lee un calendario de la configuración; ignora las entradas inválidas."""
    identifier = entry.get("id")
    name = entry.get("name")
    url = entry.get("ical_url")
    if not isinstance(identifier, str) or not isinstance(name, str):
        return None
    if not isinstance(url, str) or not url:
        return None
    color = entry.get("color")
    enabled = entry.get("enabled")
    return Calendar(
        id=identifier,
        name=name,
        color=color if isinstance(color, str) and color else "#4285F4",
        enabled=enabled if isinstance(enabled, bool) else True,
        ical_url=url,
    )


def load_config(path: Path | None = None) -> list[Calendar]:
    """Lee la configuración; si falta o está rota, devuelve una lista vacía."""
    target = path or config_path()
    try:
        raw = cast("object", json.loads(target.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        return []
    if not isinstance(raw, dict):
        return []
    entries = cast("dict[str, object]", raw).get("calendars")
    if not isinstance(entries, list):
        return []
    calendars: list[Calendar] = []
    for item in cast("list[object]", entries):
        if isinstance(item, dict):
            calendar = _calendar_from_entry(cast("dict[str, object]", item))
            if calendar is not None:
                calendars.append(calendar)
    return calendars


def save_config(calendars: list[Calendar], path: Path | None = None) -> None:
    """Guarda la configuración de forma atómica y sólo para el dueño."""
    target = path or config_path()
    _ = target.parent.mkdir(parents=True, exist_ok=True)
    target.parent.chmod(0o700)
    payload = {"calendars": [_config_entry(calendar) for calendar in calendars]}
    temp = target.with_suffix(f"{target.suffix}.tmp")
    _ = temp.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    temp.chmod(0o600)
    _ = temp.replace(target)
    target.chmod(0o600)


@dataclass(frozen=True, slots=True)
class Event:
    """Un evento de calendario en su zona horaria original."""

    uid: str
    summary: str
    start: datetime
    end: datetime
    all_day: bool
    rrule: str | None = None
    exdates: tuple[datetime, ...] = ()


@dataclass(frozen=True, slots=True)
class _Property:
    """Una propiedad ICS con sus parámetros."""

    name: str
    params: dict[str, str]
    value: str


def _local_zone() -> tzinfo:
    """Devuelve la zona horaria local del sistema."""
    return datetime.now().astimezone().tzinfo or UTC


def _zone(name: str | None, fallback: tzinfo) -> tzinfo:
    """Devuelve la zona indicada o la de respaldo si no se reconoce."""
    if not name:
        return fallback
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        return fallback


def _unfold(text: str) -> list[str]:
    """Desdobla las líneas ICS que continúan en la anterior."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    lines: list[str] = []
    for line in normalized.split("\n"):
        if line[:1] in {" ", "\t"} and lines:
            lines[-1] += line[1:]
        else:
            lines.append(line)
    return lines


def _split_property(line: str) -> _Property | None:
    """Separa nombre, parámetros y valor de una línea ICS."""
    if ":" not in line:
        return None
    head, _, value = line.partition(":")
    parts = head.split(";")
    name = parts[0].strip().upper()
    if not name:
        return None
    params: dict[str, str] = {}
    for part in parts[1:]:
        key, _, raw = part.partition("=")
        params[key.strip().upper()] = raw.strip().strip('"')
    return _Property(name=name, params=params, value=value.strip())


def _parse_datetime(value: str, zone: tzinfo) -> datetime:
    """Interpreta una fecha u hora ICS en la zona indicada."""
    text = value.strip()
    if text.endswith("Z"):
        stamp = datetime.strptime(text[:-1], "%Y%m%dT%H%M%S")
        return stamp.replace(tzinfo=UTC)
    if "T" in text:
        stamp = datetime.strptime(text, "%Y%m%dT%H%M%S")
    else:
        stamp = datetime.strptime(text, "%Y%m%d")
    return stamp.replace(tzinfo=zone)


def _first(props: dict[str, list[_Property]], name: str) -> _Property | None:
    """Devuelve la primera propiedad con ese nombre."""
    found = props.get(name)
    if not found:
        return None
    return found[0]


def _build_event(
    props: dict[str, list[_Property]], calendar_zone: tzinfo, index: int
) -> Event:
    """Construye un evento a partir de sus propiedades ICS."""
    start_prop = _first(props, "DTSTART")
    if start_prop is None:
        raise CalendarError("evento sin DTSTART")
    zone = _zone(start_prop.params.get("TZID"), calendar_zone)
    all_day = start_prop.params.get("VALUE", "").upper() == "DATE"
    start = _parse_datetime(start_prop.value, zone)

    end_prop = _first(props, "DTEND")
    if end_prop is None:
        end = start + (timedelta(days=1) if all_day else timedelta(hours=1))
    else:
        end = _parse_datetime(end_prop.value, _zone(end_prop.params.get("TZID"), zone))

    summary_prop = _first(props, "SUMMARY")
    summary = summary_prop.value if summary_prop else "Sin título"

    uid_prop = _first(props, "UID")
    uid = uid_prop.value if uid_prop else f"evento-{index}"

    rrule_prop = _first(props, "RRULE")
    rrule = rrule_prop.value if rrule_prop else None

    exdates: list[datetime] = []
    for prop in props.get("EXDATE", []):
        exzone = _zone(prop.params.get("TZID"), zone)
        exdates.extend(
            _parse_datetime(chunk, exzone)
            for chunk in prop.value.split(",")
            if chunk.strip()
        )

    return Event(
        uid=uid,
        summary=summary,
        start=start,
        end=end,
        all_day=all_day,
        rrule=rrule,
        exdates=tuple(exdates),
    )


def parse_ics(text: str) -> list[Event]:
    """Extrae los eventos de un documento iCalendar."""
    default_zone = _local_zone()
    calendar_zone = default_zone
    events: list[Event] = []
    current: dict[str, list[_Property]] | None = None

    for line in _unfold(text):
        prop = _split_property(line)
        if prop is None:
            continue
        if prop.name == "BEGIN":
            if prop.value.upper() == "VEVENT":
                current = {}
            continue
        if prop.name == "END":
            if prop.value.upper() == "VEVENT" and current is not None:
                events.append(_build_event(current, calendar_zone, len(events)))
                current = None
            continue
        if prop.name == "X-WR-TIMEZONE" and current is None:
            calendar_zone = _zone(prop.value, default_zone)
            continue
        if current is not None:
            current.setdefault(prop.name, []).append(prop)
    return events


def _covered_days(event: Event) -> list[date]:
    """Devuelve los días que cubre el evento en su propia zona."""
    start_day = event.start.date()
    if event.all_day:
        end_day = event.end.date() - timedelta(days=1)
    else:
        end_day = (event.end - timedelta(seconds=1)).date()
    end_day = max(end_day, start_day)
    return [
        start_day + timedelta(days=offset)
        for offset in range((end_day - start_day).days + 1)
    ]


def _overlaps_range(event: Event, date_from: date, date_to: date) -> bool:
    """Dice si el evento toca el rango pedido."""
    return any(date_from <= day <= date_to for day in _covered_days(event))


def _rule_occurrences(
    rule: str, start: datetime, date_from: date, date_to: date
) -> list[datetime]:
    """Devuelve las ocurrencias de una regla dentro del rango pedido."""
    try:
        from dateutil.rrule import rrulestr
    except ModuleNotFoundError as error:
        raise CalendarError(
            "falta python3-dateutil; instálalo con: sudo apt install python3-dateutil"
        ) from error
    recurrence = rrulestr(rule, dtstart=start)
    after = datetime.combine(
        date_from, time.min, tzinfo=start.tzinfo
    ) - timedelta(days=1)
    before = datetime.combine(date_to, time.max, tzinfo=start.tzinfo)
    return list(recurrence.between(after, before, inc=True))


def expand_events(
    events: list[Event], date_from: date, date_to: date
) -> list[Event]:
    """Devuelve los eventos del rango pedido, con las recurrencias expandidas."""
    if date_to < date_from:
        return []
    expanded: list[Event] = []
    for event in events:
        if event.rrule is None:
            if _overlaps_range(event, date_from, date_to):
                expanded.append(replace(event, rrule=None, exdates=()))
            continue
        duration = event.end - event.start
        occurrences = _rule_occurrences(
            event.rrule, event.start, date_from, date_to
        )
        for occurrence in occurrences:
            if occurrence in event.exdates:
                continue
            candidate = replace(
                event,
                start=occurrence,
                end=occurrence + duration,
                rrule=None,
                exdates=(),
            )
            if _overlaps_range(candidate, date_from, date_to):
                expanded.append(candidate)
    return expanded


def group_by_day(events: list[Event]) -> dict[str, list[Event]]:
    """Agrupa los eventos por día, en la zona de cada evento."""
    by_day: dict[str, list[Event]] = {}
    for event in events:
        for day in _covered_days(event):
            by_day.setdefault(day.isoformat(), []).append(event)
    for day_events in by_day.values():
        day_events.sort(key=lambda item: (not item.all_day, item.start))
    return by_day


def fetch_ics(url: str, timeout: float = 10.0) -> str:
    """Descarga el documento iCal de una URL."""
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise CalendarError("la dirección debe empezar por http:// o https://")
    request = Request(url, headers={"User-Agent": "Caparazon/1.0"})
    try:
        opened = cast("HTTPResponse", urlopen(request, timeout=timeout))
        with opened as response:
            charset = response.headers.get_content_charset() or "utf-8"
            return response.read().decode(charset, errors="replace")
    except (URLError, TimeoutError, OSError) as error:
        raise CalendarError("no se pudo descargar el calendario") from error


def validate_url(url: str) -> str:
    """Descarga la dirección y comprueba que responde con un calendario iCal."""
    text = fetch_ics(url)
    if "BEGIN:VCALENDAR" not in text:
        raise CalendarError("la dirección no responde con un calendario iCal")
    return text


def read_cached_ics(
    calendar_id: str, max_age: int = 900, cache_path: Path | None = None
) -> str | None:
    """Lee el ICS cacheado mientras siga vigente."""
    directory = cache_path or cache_dir()
    file = directory / f"{calendar_id}.ics"
    try:
        age = datetime.now(UTC).timestamp() - file.stat().st_mtime
    except OSError:
        return None
    if age > max_age:
        return None
    try:
        return file.read_text(encoding="utf-8")
    except OSError:
        return None


def write_cached_ics(
    calendar_id: str, text: str, cache_path: Path | None = None
) -> None:
    """Guarda el ICS crudo para no volver a descargarlo."""
    directory = cache_path or cache_dir()
    _ = directory.mkdir(parents=True, exist_ok=True)
    directory.chmod(0o700)
    file = directory / f"{calendar_id}.ics"
    temp = file.with_suffix(".ics.tmp")
    _ = temp.write_text(text, encoding="utf-8")
    _ = temp.replace(file)


def event_to_json(event: Event, calendar: Calendar) -> dict[str, object]:
    """Convierte un evento al formato que consume la shell."""
    return {
        "id": f"{calendar.id}:{event.uid}",
        "calendar_id": calendar.id,
        "calendar_name": calendar.name,
        "color": calendar.color,
        "name": event.summary,
        "all_day": event.all_day,
        "start": (
            event.start.date().isoformat() if event.all_day else event.start.isoformat()
        ),
        "end": event.end.date().isoformat() if event.all_day else event.end.isoformat(),
    }


def build_payload(
    calendars: list[Calendar],
    date_from: date,
    date_to: date,
    *,
    fetcher: Callable[[str], str] = fetch_ics,
    cache_max_age: int = 900,
    cache_path: Path | None = None,
) -> dict[str, object]:
    """Construye el JSON con los eventos del rango pedido."""
    by_day: dict[str, list[dict[str, object]]] = {}
    errors: list[dict[str, str]] = []
    stale = False
    for calendar in calendars:
        if not calendar.enabled:
            continue
        text = read_cached_ics(
            calendar.id, max_age=cache_max_age, cache_path=cache_path
        )
        if text is None:
            try:
                text = fetcher(calendar.ical_url)
                write_cached_ics(calendar.id, text, cache_path=cache_path)
            except CalendarError as error:
                cached = read_cached_ics(
                    calendar.id, max_age=10**9, cache_path=cache_path
                )
                errors.append(
                    {"id": calendar.id, "name": calendar.name, "message": str(error)}
                )
                if cached is None:
                    continue
                text = cached
                stale = True
        events = expand_events(parse_ics(text), date_from, date_to)
        for day, day_events in group_by_day(events).items():
            by_day.setdefault(day, []).extend(
                event_to_json(event, calendar) for event in day_events
            )
    for day_events in by_day.values():
        day_events.sort(key=lambda item: str(item["start"]))
    return {
        "ok": not errors,
        "calendars": [calendar_to_json(calendar) for calendar in calendars],
        "by_day": by_day,
        "stale": stale,
        "errors": errors,
    }


def _calendar_name_from_ics(text: str, fallback: str) -> str:
    """Lee el nombre del calendario del propio ICS."""
    for line in _unfold(text):
        prop = _split_property(line)
        if prop is not None and prop.name == "X-WR-CALNAME" and prop.value:
            return prop.value
    return fallback


def _free_color(calendars: list[Calendar]) -> str:
    """Devuelve el primer color de la paleta que nobody usa."""
    used = {calendar.color.upper() for calendar in calendars}
    for color in PALETTE:
        if color.upper() not in used:
            return color
    return PALETTE[0]


def _find_calendar(calendars: list[Calendar], identifier: str) -> Calendar:
    """Busca un calendario por identificador."""
    for calendar in calendars:
        if calendar.id == identifier:
            return calendar
    raise CalendarError(f"no existe el calendario '{identifier}'")


def _parse_iso_date(value: str) -> date:
    """Interpreta una fecha en formato ISO."""
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise CalendarError("las fechas deben tener el formato AAAA-MM-DD") from error


def _parse_color(value: str) -> str:
    """Valida un color hexadecimal."""
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        raise CalendarError("el color debe tener el formato #rrggbb")
    return value.upper()


def _parse_bool(value: str) -> bool:
    """Interpreta un booleano textual."""
    if value.lower() in {"true", "1", "si", "sí"}:
        return True
    if value.lower() in {"false", "0", "no"}:
        return False
    raise CalendarError("el valor debe ser true o false")


@dataclass
class Options:
    """Opciones ya tipadas de la línea de comandos."""

    config: Path | None = None
    cache_dir: Path | None = None
    command: str = ""
    date_from: str = ""
    date_to: str = ""
    url: str = ""
    name: str = ""
    color: str = ""
    id: str = ""
    value: str = ""


def _build_parser() -> argparse.ArgumentParser:
    """Construye el analizador de la línea de comandos."""
    parser = argparse.ArgumentParser(
        prog="gcal.py", description="Calendarios iCal para Caparazón"
    )
    _ = parser.add_argument("--config", type=Path, default=None)
    _ = parser.add_argument("--cache-dir", type=Path, default=None)
    commands = parser.add_subparsers(dest="command", required=True)

    _ = commands.add_parser("calendars", help="lista los calendarios vinculados")

    events = commands.add_parser("events", help="eventos de un rango")
    _ = events.add_argument("--from", dest="date_from", required=True)
    _ = events.add_argument("--to", dest="date_to", required=True)

    set_url = commands.add_parser("set-url", help="vincula un calendario")
    _ = set_url.add_argument("url")
    _ = set_url.add_argument("--name", default="")
    _ = set_url.add_argument("--color", default="")

    remove = commands.add_parser("remove", help="quita un calendario")
    _ = remove.add_argument("id")

    set_enabled = commands.add_parser("set-enabled", help="activa o desactiva")
    _ = set_enabled.add_argument("id")
    _ = set_enabled.add_argument("value")

    set_name = commands.add_parser("set-name", help="renombra un calendario")
    _ = set_name.add_argument("id")
    _ = set_name.add_argument("name")

    set_color = commands.add_parser("set-color", help="recolorea un calendario")
    _ = set_color.add_argument("id")
    _ = set_color.add_argument("color")
    return parser


def _command_calendars(options: Options) -> dict[str, object]:
    """Devuelve la lista de calendarios vinculados."""
    calendars = load_config(options.config)
    return {"ok": True, "calendars": [calendar_to_json(item) for item in calendars]}


def _command_events(options: Options) -> dict[str, object]:
    """Devuelve los eventos del rango pedido."""
    calendars = load_config(options.config)
    date_from = _parse_iso_date(options.date_from)
    date_to = _parse_iso_date(options.date_to)
    return build_payload(calendars, date_from, date_to, cache_path=options.cache_dir)


def _command_set_url(options: Options) -> dict[str, object]:
    """Vincula un calendario nuevo tras validar su dirección."""
    calendars = load_config(options.config)
    text = validate_url(options.url)
    name = options.name or _calendar_name_from_ics(text, "Calendario")
    color = _parse_color(options.color) if options.color else _free_color(calendars)
    identifier = unique_id(name, calendars)
    calendars.append(
        Calendar(
            id=identifier,
            name=name,
            color=color,
            enabled=True,
            ical_url=options.url,
        )
    )
    save_config(calendars, path=options.config)
    return {"ok": True, "id": identifier, "name": name, "color": color}


def _command_remove(options: Options) -> dict[str, object]:
    """Quita un calendario vinculado."""
    calendars = load_config(options.config)
    remaining = [item for item in calendars if item.id != options.id]
    if len(remaining) == len(calendars):
        raise CalendarError(f"no existe el calendario '{options.id}'")
    save_config(remaining, path=options.config)
    return {"ok": True, "id": options.id}


def _replace_calendar(
    calendars: list[Calendar], options: Options, **changes: object
) -> list[Calendar]:
    """Devuelve la lista con el calendario indicado modificado."""
    _ = _find_calendar(calendars, options.id)
    updated: list[Calendar] = []
    for item in calendars:
        if item.id != options.id:
            updated.append(item)
            continue
        updated.append(
            Calendar(
                id=item.id,
                name=cast("str", changes.get("name", item.name)),
                color=cast("str", changes.get("color", item.color)),
                enabled=cast("bool", changes.get("enabled", item.enabled)),
                ical_url=item.ical_url,
            )
        )
    return updated


def _command_set_enabled(options: Options) -> dict[str, object]:
    """Activa o desactiva un calendario."""
    calendars = load_config(options.config)
    enabled = _parse_bool(options.value)
    updated = _replace_calendar(calendars, options, enabled=enabled)
    save_config(updated, path=options.config)
    return {"ok": True, "id": options.id, "enabled": enabled}


def _command_set_name(options: Options) -> dict[str, object]:
    """Renombra un calendario."""
    calendars = load_config(options.config)
    updated = _replace_calendar(calendars, options, name=options.name)
    save_config(updated, path=options.config)
    return {"ok": True, "id": options.id, "name": options.name}


def _command_set_color(options: Options) -> dict[str, object]:
    """Recolorea un calendario."""
    calendars = load_config(options.config)
    color = _parse_color(options.color)
    updated = _replace_calendar(calendars, options, color=color)
    save_config(updated, path=options.config)
    return {"ok": True, "id": options.id, "color": color}


_COMMANDS: dict[str, Callable[[Options], dict[str, object]]] = {
    "calendars": _command_calendars,
    "events": _command_events,
    "set-url": _command_set_url,
    "remove": _command_remove,
    "set-enabled": _command_set_enabled,
    "set-name": _command_set_name,
    "set-color": _command_set_color,
}


def main(argv: list[str]) -> int:
    """Ejecuta la línea de comandos del script de calendarios."""
    parser = _build_parser()
    options = parser.parse_args(argv, namespace=Options())
    handler = _COMMANDS[options.command]
    try:
        payload = handler(options)
    except CalendarError as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

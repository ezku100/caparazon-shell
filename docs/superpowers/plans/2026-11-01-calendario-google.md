# Calendario de Google en la categoría Calendario — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vincular uno o varios calendarios de Google por URL secreta de iCal desde la propia shell, y mostrar sus eventos con puntos de color en la rejilla y una lista del día que se conmuta con el historial de notificaciones.

**Architecture:** Un script Python (`gcal.py`) hace todo el trabajo sucio: valida y guarda las URLs con permisos 600, descarga el ICS con caché de 15 minutos, lo parsea, expande recurrencias con `dateutil` y publica un JSON normalizado. Un `CalendarService.qml` lo invoca con `Process` y `StdioCollector` (molde de `WeatherService.qml`) y expone `calendars` y `byDay`. `CalendarPanel.qml` gana un conmutador de vistas en la columna izquierda, selección de día y puntos de color; `CalendarLinkDialog.qml` es el overlay donde se pega la URL. La vista elegida se recuerda en `PanelSettings.qml`.

**Tech Stack:** QML (Quickshell 0.3.2), Python 3 (script con `dateutil`, sin OAuth), JavaScript puro (`.pragma library`), pytest + node (patrón de tests del repo).

**Spec:** `docs/superpowers/specs/2026-11-01-calendario-google-design.md`

## Global Constraints

- Idioma de código, comentarios, tests y textos de UI: **español**.
- Sólo lectura. Sin OAuth, sin proyecto de Google Cloud, sin escritura de eventos.
- La URL secreta es una credencial: `chmod 600`, nunca en logs, stdout ni mensajes de error.
- Sin `QtQuick.Controls`: el diálogo usa `TextInput` de QtQuick y los tokens de `Theme`.
- No se tocan la barra, el dock ni el tema.
- `uv run pytest -q` en verde; `uv run ruff check` y `uv run basedpyright` limpios.
- Módulos JS puros con `.pragma library`, probados con un harness de node en `tests/support/` que imprime JSON de casos `{id: {ok, expected, value, detail}}`.
- Tests de QML: comprobaciones estáticas de texto sobre el `.qml` (helper `contents(path)`).
- Escrituras de configuración atómicas (`tmp` + `mv`) con permisos 600.
- Config: `~/.config/caparazon/calendar.json`. Caché: `~/.cache/caparazon/calendar/<id>.ics` + `<id>.meta.json`. Vista recordada: `~/.cache/caparazon/secondmenu.json`.
- Rango de expansión: mes visible ± 1 mes.
- Zona horaria: se conserva la hora de pared del evento; la clave de día se calcula en su propia zona.
- Sin capturas de pantalla: la verificación visual la hace el usuario.

## Review Focus

- **Feed caído o sin red**: la vista de eventos debe seguir mostrando lo último cacheado (`stale: true`) y nunca vaciarse en silencio; sin caché, "Sin eventos este día" y ningún fallo QML.
- **URL inválida o caducada (404)**: el diálogo debe decir que la URL no responde con un calendario iCal, sin repetir la URL, y el resto de calendarios debe seguir funcionando.
- **`calendar.json` corrupto, vacío o con permisos abiertos**: la shell no debe fallar; se trata como "sin calendarios" sin borrar el archivo del usuario.
- **Recurrencia mensual con `BYDAY=2TU` y `EXDATE`**: debe caer en el segundo martes de cada mes y desaparecer en las fechas excluidas.
- **Evento que cruza medianoche**: debe aparecer en los dos días que cubre, no sólo en el de inicio.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `modules/secondmenu/gcal.py` (crear) | ICS, recurrencias, config, caché y CLI. Único dueño de la credencial |
| `modules/secondmenu/CalendarService.qml` (crear) | Invoca `gcal.py`, expone `calendars` y `byDay` a QML |
| `modules/secondmenu/PanelSettings.qml` (crear) | Recuerda `notifications` vs `events` |
| `modules/secondmenu/DayEvents.qml` (crear) | Lista mixta cronológica del día seleccionado |
| `modules/secondmenu/CalendarLinkDialog.qml` (crear) | Overlay para vincular, renombrar, recolorear y quitar calendarios |
| `modules/secondmenu/CalendarPanel.qml` (modificar) | Conmutador, selección de día, puntos, badge "G" |
| `modules/secondmenu/CalendarMath.js` (modificar) | `dayKey`, `isSameDay`, `colorsForDay` |
| `modules/secondmenu/SecondMenu.qml` (modificar) | `Escape` con overlay abierto |
| `install.sh` (modificar) | Exige `python3-dateutil` |
| `pyproject.toml` (modificar) | `pythonpath`, `python-dateutil`, `types-python-dateutil`, include de ruff/basedpyright |
| `tests/support/calendario-ejemplo.ics` (crear) | Fixture ICS con puntual, todo el día, recurrente, `EXDATE` y medianoche |
| `tests/support/calendar_math_harness.js` (modificar) | Casos nuevos de día y color |
| `tests/test_gcal.py` (crear) | Contrato del script Python |
| `tests/test_calendar_google.py` (crear) | Contrato estático de los QML y del cableado |

---

### Task 1: `gcal.py` — parseo de ICS y recurrencias

**Files:**
- Create: `modules/secondmenu/gcal.py`
- Create: `tests/support/calendario-ejemplo.ics`
- Create: `tests/test_gcal.py`
- Modify: `pyproject.toml` (dependencias, `pythonpath`, include de ruff y basedpyright)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `@dataclass(frozen=True, slots=True) class Event`: `uid: str`, `summary: str`, `start: datetime`, `end: datetime`, `all_day: bool`, `rrule: str | None`, `exdates: tuple[datetime, ...]`
  - `class CalendarError(Exception)`
  - `parse_ics(text: str) -> list[Event]`
  - `expand_events(events: list[Event], date_from: date, date_to: date) -> list[Event]`
  - `group_by_day(events: list[Event]) -> dict[str, list[Event]]` (claves `YYYY-MM-DD`, en la zona del evento)

- [ ] **Step 1: Preparar dependencias y el fixture**

En `pyproject.toml`: añade `pythonpath = ["."]` a `[tool.pytest.ini_options]`, `"python-dateutil>=2.9"` a `[project].dependencies`, `"types-python-dateutil"` al grupo `dev`, `"modules/secondmenu/gcal.py"` al `include` de ruff y de basedpyright.

```bash
cd ~/Projects/caparazon-shell
uv lock && uv sync
sudo apt-get install -y python3-dateutil
python3 -c "import dateutil; print(dateutil.__version__)"
```

Escribe `tests/support/calendario-ejemplo.ics` con cinco eventos: uno puntual (`20261103T090000` con `TZID=America/Mexico_City`, SUMMARY `Daily sync`), uno de todo el día (`DTSTART;VALUE=DATE:20261104`), uno semanal (`RRULE:FREQ=WEEKLY;BYDAY=MO,WE`), uno mensual `RRULE:FREQ=MONTHLY;BYDAY=2TU` con un `EXDATE`, y uno que cruza medianoche (`20261105T230000` → `20261106T010000`).

- [ ] **Step 2: Write the failing test**

`tests/test_gcal.py`:

```python
"""Contrato del script de calendario: ICS, recurrencias y configuración."""

from __future__ import annotations

from datetime import date
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
FIXTURE = REPOSITORY_ROOT / "tests" / "support" / "calendario-ejemplo.ics"

from modules.secondmenu import gcal  # noqa: E402


def fixture_text() -> str:
    """Devuelve el ICS de ejemplo."""
    return FIXTURE.read_text(encoding="utf-8")


def test_parse_ics_reads_the_events() -> None:
    """El ICS de ejemplo tiene cinco eventos base."""
    events = gcal.parse_ics(fixture_text())
    assert len(events) == 5
    assert {event.summary for event in events} == {
        "Daily sync", "Feriado", "Semanal", "Segundo martes", "Madrugada",
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
    """El mensual cae el segundo martes y no en el EXDATE."""
    events = gcal.expand_events(
        gcal.parse_ics(fixture_text()), date(2026, 11, 1), date(2026, 11, 30)
    )
    days = sorted(
        event.start.date() for event in events if event.summary == "Segundo martes"
    )
    assert days == [date(2026, 11, 10)]


def test_an_event_crossing_midnight_lands_on_both_days() -> None:
    """El evento de 23:00 a 01:00 aparece en los dos días."""
    events = gcal.expand_events(
        gcal.parse_ics(fixture_text()), date(2026, 11, 1), date(2026, 11, 30)
    )
    by_day = gcal.group_by_day(events)
    assert "Madrugada" in [event.summary for event in by_day["2026-11-05"]]
    assert "Madrugada" in [event.summary for event in by_day["2026-11-06"]]
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_gcal.py -q`
Expected: FAIL con `ModuleNotFoundError: No module named 'modules.secondmenu'`.

- [ ] **Step 4: Implement `parse_ics`, `expand_events` y `group_by_day` en `modules/secondmenu/gcal.py`**

Requisitos que fijan la implementación:

- Desdoblar líneas ICS (las que empiezan por espacio continúan la anterior) y separar propiedades por el primer `:`.
- Leer `UID`, `SUMMARY`, `DTSTART`, `DTEND`, `RRULE`, `EXDATE`. `DTSTART;VALUE=DATE:YYYYMMDD` → `all_day = True`, medianoche en la zona de `X-WR-TIMEZONE` (o local si falta). `DTSTART;TZID=<zona>:...` → `datetime` con `zoneinfo.ZoneInfo(zona)`.
- `expand_events` usa `dateutil.rrule.rrulestr(rule, dtstart=start)` recortando con `between(date_from 00:00, date_to 23:59)`; descarta las fechas de `exdates`; devuelve copias con `rrule=None`.
- Importa `dateutil` de forma tolerante: si falta, `expand_events` lanza `CalendarError("falta python3-dateutil")`.
- `group_by_day` añade el evento a cada día entre su inicio y su fin (fechas en la zona del evento), así el evento de medianoche cae en los dos días.
- Sin `print` salvo en `main`; docstrings en todas las funciones públicas (`ruff` con `select = ["ALL"]`).

En `pyproject.toml`, si `ruff` marca reglas incompatibles con un CLI (`T201`, `TRY003`, `EM101`, `EM102`, `PLR0913`, `S310`), decláralas en `[tool.ruff.lint.per-file-ignores]` para `"modules/secondmenu/gcal.py"`.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_gcal.py -q && uv run ruff check modules/secondmenu/gcal.py && uv run basedpyright modules/secondmenu/gcal.py`
Expected: PASS, sin avisos.

- [ ] **Step 6: Commit**

```bash
git add modules/secondmenu/gcal.py tests/test_gcal.py tests/support/calendario-ejemplo.ics pyproject.toml uv.lock
git commit -m "Calendario: parseo de ICS y recurrencias"
```

---

### Task 2: `gcal.py` — configuración de calendarios

**Files:**
- Modify: `modules/secondmenu/gcal.py`
- Test: `tests/test_gcal.py`

**Interfaces:**
- Consumes: `CalendarError` de Task 1.
- Produces:
  - `@dataclass(frozen=True, slots=True) class Calendar`: `id: str`, `name: str`, `color: str`, `enabled: bool`, `ical_url: str`
  - `config_path() -> Path` → `~/.config/caparazon/calendar.json`
  - `cache_dir() -> Path` → `~/.cache/caparazon/calendar`
  - `load_config(path: Path | None = None) -> list[Calendar]` (archivo ausente o corrupto → `[]`)
  - `save_config(calendars: list[Calendar], path: Path | None = None) -> None` (atómico, 0o600, dir 0o700)
  - `slugify(name: str) -> str`
  - `unique_id(name: str, existing: list[Calendar]) -> str`
  - `calendar_to_json(calendar: Calendar) -> dict[str, str | bool]` → `{id, name, color, enabled, ical_tail}` (nunca `ical_url`)

- [ ] **Step 1: Write the failing test**

Añade a `tests/test_gcal.py`:

```python
def test_saving_a_config_sets_owner_only_permissions(tmp_path: Path) -> None:
    """La configuración es una credencial: sólo el dueño la lee."""
    path = tmp_path / "calendar.json"
    calendar = gcal.Calendar(
        id="trabajo", name="Trabajo", color="#4285F4",
        enabled=True, ical_url="https://example.invalid/a.ics",
    )
    gcal.save_config([calendar], path=path)
    assert path.stat().st_mode & 0o777 == 0o600


def test_a_missing_or_corrupt_config_is_empty(tmp_path: Path) -> None:
    """Sin archivo o con JSON roto, la shell ve cero calendarios."""
    missing = tmp_path / "nope.json"
    assert gcal.load_config(path=missing) == []

    broken = tmp_path / "broken.json"
    broken.write_text("{no es json", encoding="utf-8")
    assert gcal.load_config(path=broken) == []
    assert broken.exists()


def test_the_url_never_leaves_the_script(tmp_path: Path) -> None:
    """calendar_to_json no incluye la URL, sólo sus últimos cuatro caracteres."""
    calendar = gcal.Calendar(
        id="casa", name="Casa", color="#34A853",
        enabled=True, ical_url="https://calendar.google.com/ical/SECRETO1234/basic.ics",
    )
    payload = gcal.calendar_to_json(calendar)
    assert "ical_url" not in payload
    assert payload["ical_tail"] == "1234"
    assert "SECRETO1234" not in str(payload)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_gcal.py -q`
Expected: FAIL con `AttributeError: module 'gcal' has no attribute 'Calendar'`.

- [ ] **Step 3: Implement `Calendar`, `load_config`, `save_config`, `slugify`, `unique_id`, `calendar_to_json`**

Requisitos que fijan la implementación:

- `save_config`: escribe `json.dumps({"calendars": [...]}, ensure_ascii=False, indent=2)` en `<path>.tmp`, `chmod 0o600`, `os.replace`. Crea el directorio con `0o700`.
- `load_config`: `json.JSONDecodeError`, `OSError` o estructura inesperada → `[]` sin lanzar y sin borrar el archivo.
- `slugify`: minúsculas, sin acentos, espacios y signos a `-`, colapsa guiones. `unique_id` añade `-2`, `-3`… si el id ya existe.
- `ical_tail`: los últimos 4 caracteres del `path` de la URL; si la URL tiene menos, la URL entera nunca se imprime (usa los últimos 4 de lo que haya).

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_gcal.py -q && uv run ruff check modules/secondmenu/gcal.py && uv run basedpyright modules/secondmenu/gcal.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/gcal.py tests/test_gcal.py
git commit -m "Calendario: configuración con permisos 600"
```

---

### Task 3: `gcal.py` — descarga con caché y CLI

**Files:**
- Modify: `modules/secondmenu/gcal.py`
- Test: `tests/test_gcal.py`

**Interfaces:**
- Consumes: `Calendar`, `load_config`, `parse_ics`, `expand_events`, `group_by_day`, `calendar_to_json`.
- Produces:
  - `fetch_ics(url: str, timeout: float = 10.0) -> str`
  - `read_cached_ics(calendar_id: str, max_age: int = 900, cache_dir: Path | None = None) -> str | None`
  - `write_cached_ics(calendar_id: str, text: str, cache_dir: Path | None = None) -> None`
  - `validate_url(url: str) -> str` → devuelve el ICS si la URL responde con `BEGIN:VCALENDAR`
  - `build_payload(calendars: list[Calendar], date_from: date, date_to: date, fetcher: Callable[[str], str] = fetch_ics) -> dict[str, object]`
  - `main(argv: list[str]) -> int` con subcomandos `calendars`, `events --from --to`, `set-url <url> [--name] [--color]`, `remove <id>`, `set-enabled <id> <true|false>`, `set-name <id> <nombre>`, `set-color <id> <#rrggbb>`
  - Opciones globales `--config PATH` y `--cache-dir PATH`

- [ ] **Step 1: Write the failing test**

Amplía el encabezado de `tests/test_gcal.py` (los tests de esta tarea lo necesitan):

```python
import json
import subprocess
import sys

import pytest

GCAL = REPOSITORY_ROOT / "modules" / "secondmenu" / "gcal.py"
```

Y añade los tests:

```python
def test_the_cache_is_reused_and_expires(tmp_path: Path, monkeypatch) -> None:
    """Con caché fresca no se descarga; pasada la TTL sí."""
    monkeypatch.setenv("HOME", str(tmp_path))
    gcal.write_cached_ics("trabajo", "BEGIN:VCALENDAR")
    assert gcal.read_cached_ics("trabajo", max_age=900) == "BEGIN:VCALENDAR"
    assert gcal.read_cached_ics("trabajo", max_age=0) is None


def test_a_failing_feed_falls_back_to_stale_cache(tmp_path: Path, monkeypatch) -> None:
    """Si el feed falla, se sirve la caché y se marca stale."""
    monkeypatch.setenv("HOME", str(tmp_path))
    gcal.write_cached_ics("trabajo", fixture_text())
    calendar = gcal.Calendar(
        id="trabajo", name="Trabajo", color="#4285F4",
        enabled=True, ical_url="https://example.invalid/feed.ics",
    )

    def broken_fetch(url: str, timeout: float = 10.0) -> str:
        raise gcal.CalendarError("no se pudo descargar el calendario")

    payload = gcal.build_payload(
        [calendar], date(2026, 11, 1), date(2026, 11, 30), fetcher=broken_fetch
    )
    assert payload["stale"] is True
    assert "2026-11-03" in payload["by_day"]


def test_the_cli_events_command_prints_json(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """`events` imprime el JSON normalizado y no filtra la URL."""
    monkeypatch.setenv("HOME", str(tmp_path))
    config = tmp_path / "calendar.json"
    cache = tmp_path / "cache"
    calendar = gcal.Calendar(
        id="trabajo", name="Trabajo", color="#4285F4",
        enabled=True, ical_url="https://example.invalid/SECRETO/basic.ics",
    )
    gcal.save_config([calendar], path=config)
    gcal.write_cached_ics("trabajo", fixture_text(), cache_dir=cache)

    result = subprocess.run(
        [sys.executable, str(GCAL), "--config", str(config),
         "--cache-dir", str(cache), "events",
         "--from", "2026-11-01", "--to", "2026-11-30"],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0
    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert "SECRETO" not in result.stdout
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_gcal.py -q`
Expected: FAIL con `AttributeError: module 'gcal' has no attribute 'write_cached_ics'`.

- [ ] **Step 3: Implement descarga, caché, payload y CLI**

Requisitos que fijan la implementación:

- `fetch_ics`: `urllib.request.urlopen` con `timeout`; exige `https` (o `http`), rechaza esquemas raros con `CalendarError`; devuelve `text/plain` decodificado en UTF-8.
- `build_payload(..., fetcher=fetch_ics)`: por cada calendario habilitado lee caché fresca (TTL 900 s); si no hay o caducó, llama a `fetcher`; si el fetch falla y hay caché → usa la caché y añade el error a `errors`; si no hay caché → añade el error. `stale` es `true` si algún calendario usó caché por fallo. Los deshabilitados no aportan eventos.
- Payload: `{"ok": bool, "calendars": [...], "by_day": {...}, "stale": bool, "errors": [{"id", "name", "message"}]}`. Cada evento: `id`, `calendar_id`, `calendar_name`, `color`, `name`, `all_day`, `start`, `end`.
- `start`/`end`: ISO con offset para los de hora (`2026-11-03T09:00:00-06:00`) y sólo fecha (`2026-11-04`) para los de todo el día.
- `main`: cada subcomando imprime un JSON de una línea y devuelve 0; ante `CalendarError` imprime `{"ok": false, "error": "..."}` (sin URL) y devuelve 1. `set-url` valida con `validate_url` antes de guardar y usa `unique_id`.
- Tests que necesiten red usan un `http.server.ThreadingHTTPServer` en `127.0.0.1:0` sirviendo el fixture desde un hilo; nunca red real.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_gcal.py -q && uv run ruff check modules/secondmenu/gcal.py && uv run basedpyright modules/secondmenu/gcal.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/gcal.py tests/test_gcal.py
git commit -m "Calendario: descarga con cache y CLI"
```

---

### Task 4: `CalendarMath.js` — helpers de día y color

**Files:**
- Modify: `modules/secondmenu/CalendarMath.js`
- Modify: `tests/support/calendar_math_harness.js`
- Test: `tests/test_calendar_math.py` (los casos nuevos entran solos por el harness)

**Interfaces:**
- Consumes: nada.
- Produces:
  - `dayKey(year, month, day) -> string` (`"YYYY-MM-DD"`, mes y día con dos dígitos)
  - `isSameDay(a, b) -> boolean` (`a`, `b` = `{year, month, day}`)
  - `colorsForDay(byDay, year, month, day, order) -> string[]` (`byDay` = objeto `clave -> [eventos]`; `order` = ids de calendario en orden de configuración; devuelve colores distintos, sin tope)

- [ ] **Step 1: Write the failing test**

En `tests/support/calendar_math_harness.js`, añade casos al array `cases`:

```js
    {
        id: "clave-dia",
        detail: "dayKey rellena mes y día con dos dígitos",
        run: () => dayKey(2026, 3, 7),
        expected: "2026-03-07",
    },
    {
        id: "mismo-dia-si",
        detail: "isSameDay compara año, mes y día",
        run: () => isSameDay({ year: 2026, month: 11, day: 3 }, { year: 2026, month: 11, day: 3 }),
        expected: true,
    },
    {
        id: "mismo-dia-no",
        detail: "isSameDay distingue días distintos",
        run: () => isSameDay({ year: 2026, month: 11, day: 3 }, { year: 2026, month: 11, day: 4 }),
        expected: false,
    },
    {
        id: "colores-orden-config",
        detail: "colorsForDay devuelve colores distintos en el orden de la configuración",
        run: () => {
            const byDay = {
                "2026-11-03": [
                    { calendar_id: "casa", color: "#34A853" },
                    { calendar_id: "trabajo", color: "#4285F4" },
                    { calendar_id: "trabajo", color: "#4285F4" },
                ],
            };
            return JSON.stringify(colorsForDay(byDay, 2026, 11, 3, ["trabajo", "casa"]));
        },
        expected: '["#4285F4","#34A853"]',
    },
    {
        id: "colores-dia-vacio",
        detail: "un día sin eventos no tiene colores",
        run: () => JSON.stringify(colorsForDay({}, 2026, 11, 3, [])),
        expected: "[]",
    },
```

Y añade `dayKey, isSameDay, colorsForDay` a la desestructuración de `context` al principio del harness.

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_calendar_math.py -q -k "clave-dia or mismo-dia or colores"`
Expected: FAIL; los valores devueltos son `"error: dayKey is not defined"`.

- [ ] **Step 3: Implementar las tres funciones en `modules/secondmenu/CalendarMath.js`**

`colorsForDay` recorre `order`; por cada id busca si algún evento del día tiene ese `calendar_id` y añade su color una sola vez; los ids que no estén en `order` van al final en el orden en que aparecen en `byDay`.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_calendar_math.py -q`
Expected: PASS (incluye los casos antiguos de la rejilla).

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/CalendarMath.js tests/support/calendar_math_harness.js
git commit -m "Calendario: helpers de dia y color"
```

---

### Task 5: `CalendarService.qml`

**Files:**
- Create: `modules/secondmenu/CalendarService.qml`
- Create: `tests/test_calendar_google.py`
- Modify: `modules/secondmenu/CalendarPanel.qml` (sólo instanciar el servicio)

**Interfaces:**
- Consumes: `gcal.py events --from --to`.
- Produces:
  - `property var calendars: []` (`{id, name, color, enabled, ical_tail}`)
  - `property var byDay: ({})`
  - `property bool ready: false`
  - `property bool linked: false` (algún calendario habilitado)
  - `property bool stale: false`
  - `property var errors: []`
  - `property string rangeFrom: ""`, `property string rangeTo: ""`
  - `function refresh()`
  - `function setRange(from: string, to: string)`
  - `function eventsForDay(key: string) -> array`
  - `function calendarIds() -> array`

- [ ] **Step 1: Write the failing test**

`tests/test_calendar_google.py`:

```python
"""Contrato del calendario de Google en la categoría Calendario."""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SERVICE = REPOSITORY_ROOT / "modules" / "secondmenu" / "CalendarService.qml"


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
        "property var calendars", "property var byDay", "property bool linked",
        "property bool stale", "function refresh", "function setRange",
        "function eventsForDay", "function calendarIds",
    ):
        assert name in service
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_calendar_google.py -q`
Expected: FAIL con `FileNotFoundError` (el `.qml` no existe).

- [ ] **Step 3: Implement `CalendarService.qml`**

Molde de `WeatherService.qml`: `Process` con `command: ["python3", root.scriptPath, "events", "--from", root.rangeFrom, "--to", root.rangeTo]`, `StdioCollector` que hace `JSON.parse` y llena `calendars`, `byDay`, `stale`, `errors`; `ready` sólo si `ok` es `true`. `Timer` de 900000 ms y refresco al completar. `setRange` sólo refresca si el rango cambió. `eventsForDay(key)` devuelve `byDay[key] || []`. `calendarIds()` devuelve los ids habilitados en orden.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_calendar_google.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/CalendarService.qml tests/test_calendar_google.py
git commit -m "Calendario: servicio de eventos con el molde del clima"
```

---

### Task 6: `PanelSettings.qml` — memoria de la vista

**Files:**
- Create: `modules/secondmenu/PanelSettings.qml`
- Test: `tests/test_calendar_google.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `property string view: "notifications"` (`"notifications"` o `"events"`)
  - `property bool loaded: false`
  - `function setView(value: string)`
  - `readonly property string settingsPath` → `~/.cache/caparazon/secondmenu.json`

- [ ] **Step 1: Write the failing test**

```python
SETTINGS = REPOSITORY_ROOT / "modules" / "secondmenu" / "PanelSettings.qml"


def test_the_view_is_remembered_in_the_cache() -> None:
    """La preferencia vive en la caché de Caparazón, como la de Música."""
    settings = contents(SETTINGS)
    assert ".cache/caparazon" in settings
    assert "secondmenu.json" in settings
    assert 'property string view' in settings
    assert "notifications" in settings
    assert '"events"' in settings or "'events'" in settings


def test_the_setting_is_written_atomically() -> None:
    """Se escribe a un .tmp y se renombra, sin dejar el JSON a medias."""
    settings = contents(SETTINGS)
    assert ".tmp" in settings
    assert "mv " in settings or "os.replace" in settings
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_calendar_google.py -q -k "view or setting"`
Expected: FAIL con `FileNotFoundError`.

- [ ] **Step 3: Implement `PanelSettings.qml`**

Molde de `MusicSettings.qml` para leer (`FileView` + `JsonAdapter` con `watchChanges` y bandera `loaded`), pero la escritura va por `Process` con `bash -c` que valida el valor contra los dos permitidos y hace `printf ... > "$2.tmp" && mv "$2.tmp" "$2"`, seguido de `file.reload()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_calendar_google.py -q -k "view or setting"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/PanelSettings.qml tests/test_calendar_google.py
git commit -m "Calendario: recordar la vista de la columna"
```

---

### Task 7: `DayEvents.qml` — lista mixta del día

**Files:**
- Create: `modules/secondmenu/DayEvents.qml`
- Test: `tests/test_calendar_google.py`

**Interfaces:**
- Consumes: array de eventos `{id, calendar_id, calendar_name, color, name, all_day, start, end}`.
- Produces: `property var events: []`; `readonly property string emptyLabel: "Sin eventos este día"`.

- [ ] **Step 1: Write the failing test**

```python
DAY_EVENTS = REPOSITORY_ROOT / "modules" / "secondmenu" / "DayEvents.qml"


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
    assert "radius: 4" in panel or "radius: 3" in panel
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_calendar_google.py -q -k "day_list"`
Expected: FAIL con `FileNotFoundError`.

- [ ] **Step 3: Implement `DayEvents.qml`**

`ListView` con `spacing: 10`, filas de ~40 px: punto de 8 px con el color del evento; hora `09:00` (subcadena `start.substr(11, 5)` cuando `all_day` es falso, `Todo el día` cuando es verdadero); nombre del calendario a la derecha en 9 px `Theme.textDim`; título debajo en 11 px `Theme.text` con `elide: Text.ElideRight`. Vacío: texto centrado `root.emptyLabel` en 11 px `Theme.textDim`. Sin fondo propio: la tarjeta la pone quien lo usa.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_calendar_google.py -q -k "day_list"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/DayEvents.qml tests/test_calendar_google.py
git commit -m "Calendario: lista mixta de eventos del dia"
```

---

### Task 8: `CalendarPanel.qml` — conmutador, selección, puntos y badge

**Files:**
- Modify: `modules/secondmenu/CalendarPanel.qml`
- Test: `tests/test_calendar_google.py`

**Interfaces:**
- Consumes: `CalendarService` (Task 5), `PanelSettings` (Task 6), `DayEvents` (Task 7), `CalendarMath` (Task 4).
- Produces:
  - `property string view` (`"notifications"`/`"events"`)
  - `property var selectedDay: ({year, month, day})`
  - `signal overlayChanged(bool open)`
  - `function setView(value: string)`
  - `function selectDay(year: int, month: int, day: int)`

- [ ] **Step 1: Write the failing test**

```python
CALENDAR_PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "CalendarPanel.qml"


def test_the_column_switches_between_history_and_events() -> None:
    """Las flechitas cambian la vista y la etiqueta lo dice."""
    panel = contents(CALENDAR_PANEL)
    assert "PanelSettings" in panel
    assert "NotificationHistory" in panel
    assert "DayEvents" in panel
    assert '"Eventos"' in panel or "'Eventos'" in panel
    assert '"Notificaciones"' in panel or "'Notificaciones'" in panel


def test_the_clear_button_only_exists_in_the_history_view() -> None:
    """Limpiar no tiene sentido en la vista de eventos."""
    panel = contents(CALENDAR_PANEL)
    assert 'root.view === "notifications"' in panel


def test_the_grid_selects_a_day() -> None:
    """Clic en una celda selecciona el día, con marca distinta de hoy."""
    panel = contents(CALENDAR_PANEL)
    assert "selectDay" in panel
    assert "selectedDay" in panel


def test_the_grid_draws_colour_dots() -> None:
    """Los días con eventos llevan puntos de color, con tope de tres."""
    panel = contents(CALENDAR_PANEL)
    assert "colorsForDay" in panel
    assert "length > 3" in panel


def test_the_google_badge_opens_the_dialog() -> None:
    """El badge G vive en la esquina izquierda de la fila del mes."""
    panel = contents(CALENDAR_PANEL)
    assert "CalendarLinkDialog" in panel
    assert "overlayChanged" in panel
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_calendar_google.py -q -k "column or clear or grid or badge"`
Expected: FAIL en las aserciones nuevas.

- [ ] **Step 3: Implementar los cambios en `CalendarPanel.qml`**

- Instanciar `PanelSettings { id: settings }`, `CalendarService { id: calendar }` y `CalendarLinkDialog { id: linkDialog }`; `root.view` se lee de `settings` y `setView` delega en `settings.setView`.
- `selectedDay` arranca en hoy; `resetToToday()` también lo devuelve a hoy; `shiftMonth` conserva el número de día si existe en el mes nuevo y si no usa el último día.
- La columna izquierda: fila de título con `‹`, la etiqueta según `root.view`, `›` y, sólo en notificaciones, el botón "Limpiar". Debajo, `NotificationHistory` o `DayEvents` (con `events: calendar.eventsForDay(Cal.dayKey(selectedDay.year, selectedDay.month, selectedDay.day))`).
- Rejilla: `MouseArea` por celda que llama `selectDay(cell.year, cell.month, cell.day)`; anillo `Theme.m3Primary` de 1 px para el seleccionado (además del relleno de hoy); puntos: `Cal.colorsForDay(calendar.byDay, cell.year, cell.month, cell.day, calendar.calendarIds())`, máximo tres, y un punto `Theme.textDim` si hay más de tres.
- Badge "G": `Rectangle` de 22 px en `monthHeader` alineado a la izquierda, `Text { text: "G"; color: "#4285F4" }`, atenuado si `!calendar.linked`; `MouseArea` que abre `linkDialog`.
- `CalendarLinkDialog` recibe `calendars: calendar.calendars`, emite `overlayChanged(linkDialog.opened)` y `changed()` → `calendar.refresh()`.
- El rango del servicio: `calendar.setRange(...)` con el primer y último día del mes visible ± 1 mes, recalculado en `onViewYearChanged`/`onViewMonthChanged`.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_calendar_google.py -q && uv run pytest -q`
Expected: PASS en todo.

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/CalendarPanel.qml tests/test_calendar_google.py
git commit -m "Calendario: conmutador de vistas, seleccion y puntos"
```

---

### Task 9: `CalendarLinkDialog.qml` — vincular desde la shell

**Files:**
- Create: `modules/secondmenu/CalendarLinkDialog.qml`
- Test: `tests/test_calendar_google.py`

**Interfaces:**
- Consumes: `gcal.py set-url | remove | set-enabled | set-name | set-color`; `wl-paste`; `xdg-open`.
- Produces:
  - `property var calendars: []`
  - `property bool opened: false`
  - `property string statusText: ""`
  - `property bool busy: false`
  - `signal closed()`
  - `signal changed()`

- [ ] **Step 1: Write the failing test**

```python
DIALOG = REPOSITORY_ROOT / "modules" / "secondmenu" / "CalendarLinkDialog.qml"


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


def test_the_dialog_reports_an_invalid_url_without_repeating_it() -> None:
    """El mensaje de error no repite la URL pegada."""
    dialog = contents(DIALOG)
    assert "no responde con un calendario iCal" in dialog
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_calendar_google.py -q -k "dialog"`
Expected: FAIL con `FileNotFoundError`.

- [ ] **Step 3: Implement `CalendarLinkDialog.qml`**

Overlay de ~380x300 centrado sobre la tarjeta del calendario, con `Theme.surface`, radio 20 y borde `Theme.m3OutlineVariant`; se ve sólo con `opened`.

- Cabecera "Vincular calendarios" y cierre.
- Lista de `calendars`: punto de color (clic → muestra ocho muestras y llama `set-color`), nombre editable (`TextInput` → `set-name` al perder foco), casilla de activación (`set-enabled`), botón de quitar (`remove`).
- Alta: botón "Abrir ajustes de Google" (`Process` → `xdg-open https://calendar.google.com/calendar/settings`), `TextInput` para la URL, botón "Pegar" (`Process` → `wl-paste --no-newline`), botón "Guardar" (`Process` → `python3 gcal.py set-url <url> --name <nombre> --color <color>`), y `statusText` con el resultado.
- Todos los comandos escriben en un `Process` y leen el JSON de stdout; al terminar con `ok`, emiten `changed()`. Los errores se muestran en `statusText` tal cual vienen del script (nunca incluyen la URL).
- `opened` se controla desde el panel; al cerrar emite `closed()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_calendar_google.py -q -k "dialog"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/CalendarLinkDialog.qml tests/test_calendar_google.py
git commit -m "Calendario: dialogo para vincular calendarios"
```

---

### Task 10: `SecondMenu.qml` — Escape y foco con el overlay

**Files:**
- Modify: `modules/secondmenu/SecondMenu.qml`
- Test: `tests/test_calendar_google.py`

**Interfaces:**
- Consumes: `CalendarPanel.overlayChanged(bool)` de Task 8.
- Produces: `property bool overlayOpen: false`.

- [ ] **Step 1: Write the failing test**

```python
SECOND_MENU = REPOSITORY_ROOT / "modules" / "secondmenu" / "SecondMenu.qml"


def test_escape_closes_the_dialog_before_the_menu() -> None:
    """Con el overlay abierto, Escape no debe cerrar el menú entero."""
    menu = contents(SECOND_MENU)
    assert "overlayOpen" in menu
    assert "enabled: root.active && !root.overlayOpen" in menu
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_calendar_google.py -q -k "escape"`
Expected: FAIL: `overlayOpen` no existe.

- [ ] **Step 3: Implementar en `SecondMenu.qml`**

Añade `property bool overlayOpen: false`; en `calendarComponent` cablea `onOverlayChanged: (open) => root.overlayOpen = open`; cambia el `Shortcut` de `Escape` a `enabled: root.active && !root.overlayOpen`.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_calendar_google.py -q && uv run pytest -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/secondmenu/SecondMenu.qml tests/test_calendar_google.py
git commit -m "Calendario: Escape cierra el dialogo antes que el menu"
```

---

### Task 11: `install.sh`, README y verificación en vivo

**Files:**
- Modify: `install.sh`
- Modify: `README.md`
- Test: `tests/test_calendar_google.py`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: nada.

- [ ] **Step 1: Write the failing test**

```python
INSTALL = REPOSITORY_ROOT / "install.sh"


def test_the_installer_requires_dateutil() -> None:
    """Sin python3-dateutil las recurrencias no se expanden."""
    installer = contents(INSTALL)
    assert "python3-dateutil" in installer
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_calendar_google.py -q -k installer`
Expected: FAIL.

- [ ] **Step 3: Implementar la dependencia en `install.sh`**

Añade `SHELL_APT_PACKAGES=(python3 python3-dateutil)` y `require_shell_dependencies` (mismo patrón que `require_theme_dependencies`: comprueba con `python3 -c "import dateutil"` y, si falta, sale con el `apt install` que lo arregla). Llámala en la rama `instalar`, antes de `install_shell`.

- [ ] **Step 4: Suite completa y lint**

Run:
```bash
cd ~/Projects/caparazon-shell
uv run pytest -q
uv run ruff check
uv run basedpyright
```
Expected: toda la suite en verde, ruff y basedpyright limpios.

- [ ] **Step 5: Verificación en vivo con el usuario**

Pedir al usuario:

1. Pegar la URL secreta de un calendario real desde el badge "G" y ver "Vinculado: <nombre>".
2. Comprobar los puntos de color en la rejilla y la lista mixta del día con hora, color y calendario.
3. Conmutar con las flechitas, cambiar de día y de mes.
4. Reiniciar la shell y comprobar que la vista se recuerda.
5. Añadir un segundo calendario y ver dos colores.
6. Quitar un calendario y comprobar que sus eventos desaparecen.
7. Cortar la red y confirmar que los eventos cacheados siguen ahí.

Iterar sobre lo que el usuario vea raro (es el único juez visual: este plan no toma capturas).

- [ ] **Step 6: Actualizar el README**

Añadir a la descripción del menú secundario que la categoría Calendario muestra los eventos de uno o varios calendarios de Google (vinculados con la URL secreta de iCal desde el propio menú) y que la columna alterna entre notificaciones y eventos del día.

- [ ] **Step 7: Commit**

```bash
git add install.sh README.md tests/test_calendar_google.py
git commit -m "Calendario: dependencia dateutil y README"
```

---

## Autoevaluación del plan

**Cobertura de la especificación:**

| Punto del diseño | Tarea |
|---|---|
| Parseo de ICS, todo el día, medianoche, `EXDATE` | Task 1 |
| `calendar.json` con permisos 600 y escritura atómica | Task 2 |
| Descarga con caché de 15 min y datos viejos (`stale`) | Task 3 |
| `gcal.py` con subcomandos (vincular, quitar, activar, renombrar, recolorear) | Task 3 |
| Redacción de la URL (sólo `ical_tail`) | Task 2 + Task 9 |
| `dayKey`, `isSameDay`, `colorsForDay` | Task 4 |
| `CalendarService` con rango mes ± 1 | Task 5 + Task 8 |
| Memoria de la vista | Task 6 |
| Lista mixta con punto de color, hora y nombre del calendario | Task 7 |
| Conmutador `‹ ›`, selección de día, puntos con tope de tres, badge G | Task 8 |
| Diálogo con pegar, abrir ajustes, renombrar, recolorear, quitar | Task 9 |
| `Escape` del diálogo antes que el del menú | Task 10 |
| `python3-dateutil` obligatoria | Task 1 + Task 11 |
| Degradación sin red, sin caché, con config corrupta | Task 3 (tests) + Task 11 (paso 5.7) |

**Consistencia de tipos:** `Calendar` y `Event` se definen en Task 1/2 y son las que usan Task 3 y los tests; `colorsForDay(byDay, year, month, day, order)` se define en Task 4 y se consume en Task 8 con la misma firma; `eventsForDay(key)` de Task 5 es la que usa Task 8; `overlayChanged(bool)` de Task 8 es la que cablea Task 10; el payload (`calendars`, `by_day`, `stale`, `errors`) es el mismo que parsea Task 5 y el que consume Task 7.

**Revisión de los "Review Focus":** feed caído → Task 3 (`build_payload` con `fetcher` que falla) y Task 11 paso 5.7; URL caducada → Task 3 (`validate_url` y errores sin URL) y Task 9 (`statusText`); config corrupta → Task 2 (tests); recurrencia mensual con `BYDAY` y `EXDATE` → Task 1 (tests); evento que cruza medianoche → Task 1 (test).

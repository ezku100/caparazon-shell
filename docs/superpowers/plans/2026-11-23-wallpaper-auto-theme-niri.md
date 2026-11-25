# Plan: tema automático derivado del wallpaper en Niri

## Goal

Integrar `accent-theme` y `caparazon-shell` para que, bajo Niri, el wallpaper de Waywallen genere automáticamente paleta, temas GTK, Qt6/KColorScheme/Kvantum y estado consumible por Caparazón, sin panel manual, sin segundo servicio y sin afectar KDE/Plasma.

Estado actual: spec corregido aprobado; plan pendiente de revisión; implementación no autorizada todavía. No hay `task_id` ni delegación a subagentes premium.

## Baseline verificado

- `accent-theme`: `./.venv/bin/python -m pytest -q` → `102 passed in 6.64s`.
- `caparazon-shell`: `./.venv/bin/python -m pytest -q` → `848 passed, 1 skipped in 25.00s`.
- `accent-theme` lint: `./.venv/bin/ruff check src tests` → `All checks passed!`.
- `accent-theme` tipos: `./.venv/bin/basedpyright src/accent_theme` → `29 errors, 3 warnings, 0 notes` preexistentes; el subconjunto tocado por este plan da `0 errors, 0 warnings, 0 notes`.
- `caparazon-shell` lint sobre archivos tocados: `./.venv/bin/ruff check integration/bin/caparazon-wm.py tests/test_niri_configs_panel.py tests/test_theme_install_contract.py tests/test_install_compositor_agnostic.py` → `223 errors` preexistentes; con `tests` completo → `255 errors`.
- `caparazon-shell` tipos sobre archivos tocados: `./.venv/bin/basedpyright integration/bin/caparazon-wm.py tests/test_niri_configs_panel.py tests/test_theme_install_contract.py tests/test_install_compositor_agnostic.py` → `327 errors, 59 warnings, 0 notes` preexistentes.
- Markdown sin LSP configurado; verificación de este plan será lectura directa.

## Global Constraints (verbatim)

- `"No instalar nada de nada (ni siquiera paquetes pequeños como curl o jq). Si hace falta algo así, pedir permiso primero."`
- Permiso específico ya concedido: instalar `qt6ct` desde PikaOS. No autoriza ningún otro paquete.
- Usar skill `pikaos-sys` para cualquier paso de `apt`, con `DEBIAN_FRONTEND=noninteractive` y verificación posterior con `systemctl --failed`.
- `"No ejecutar comandos de git de lectura/escritura (git status, git diff, git log...)"`
- `"sin commits sin petición explícita"`
- `"CLI como única puerta al sistema"`
- `"TDD estricto"`
- `"no debemos afectar el funcionamiento de la shell con kde"`
- `"NO DEBE DAÑAR NI INTERRUMPIR LO QUE YA SE TIENE EN KDE CON LA SHELL"`
- `"No ejecutar install.sh contra HOME real"`
- `"No delegar a subagentes/categorías con modelos premium... Solo se vale delegar si el usuario lo pide explícito en ese mensaje."`
- `"español"`
- `"Comprobaciones visuales: pedir permiso; no mover mouse."`
- No instalar Kvantum, `qtengine`, `hyprqt6engine` ni `qt6ct-kde`.
- No poner `QT_QPA_PLATFORMTHEME` en `environment.d` ni en servicios de usuario con alcance global; sólo Niri.
- No escribir estado cuando falle la generación.
- No publicar archivos de tema si falta algún staging o si algún JSON de staging es inválido.
- No leer `kdeglobals` ni escribir configuración KDE cuando la fuente resuelta sea `waywallen`.
- No deshabilitar `accent-theme.service` ni crear un segundo servicio de watcher.

## Architecture

- `accent-theme` es el productor:
  - Lee una fuente: `kde`, `waywallen` o `auto`.
  - `auto` resuelve `waywallen` cuando `XDG_CURRENT_DESKTOP` contiene `niri`; en cualquier otro caso resuelve `kde`.
  - Usa Matugen `image` para Waywallen y mantiene Matugen `color` para KDE.
  - Valida todos los staging antes de publicar.
  - Escribe un estado JSON en `~/.cache/accent-theme/niri-state.json`.
  - Mantiene un único watcher con caché por fuente.
- `caparazon-shell` es consumidor:
  - Elimina el panel manual `app-theme`.
  - Expone `caparazon-wm theme status` como comando de sólo lectura sobre el estado de `accent-theme`.
  - Sigue consumiendo las paletas `~/.cache/caparazon/colors*.json` mediante `FileView watchChanges: true`.
- Qt:
  - El entorno de Niri usa `QT_QPA_PLATFORMTHEME=qt6ct` y `QT_QPA_PLATFORMTHEME_QT6=qt6ct`.
  - `qt6ct` lee `~/.config/qt6ct/colors/matugen.conf`.
  - KColorScheme y Kvantum se escriben como salidas derivadas, pero no se instala Kvantum ni se cambia su selector sin permiso adicional.
- Servicio:
  - `accent-theme.service` queda como único watcher: `accent-theme watch --source auto`.
  - `PassEnvironment=XDG_CURRENT_DESKTOP XDG_MENU_PREFIX` permite heredar el entorno importado por Niri sin fijar un valor de escritorio en la unit.
  - `50-startup.kdl` importa `XDG_CURRENT_DESKTOP` y reinicia `accent-theme.service` con `try-restart` para que el proceso ya corriente vea `niri`.

## Interfaces exactas

### `accent-theme`

`src/accent_theme/paths.py`:

```python
@dataclass(frozen=True, slots=True)
class ThemePaths:
    home: Path
    config_home: Path
    data_home: Path
    cache_home: Path
    templates_dir: Path
    templates_d_dir: Path
    matugen_config: Path
    user_service: Path
    kde_globals: Path
    waywallen_config: Path
    waywallen_database: Path
    niri_state: Path
```

`ThemePaths.from_environment(environ)` conserva los campos actuales y añade:

- `kde_globals = config_home.parent / "kdeglobals"` (porque `config_home` ya es `XDG_CONFIG_HOME/accent-theme`).
- `waywallen_config = home / ".var/app/org.waywallen.waywallen/config/waywallen/config.toml"`.
- `waywallen_database = home / ".var/app/org.waywallen.waywallen/data/waywallen/waywallen-v2.db"`.
- `niri_state = cache_home / "niri-state.json"` (porque `cache_home` ya es `XDG_CACHE_HOME/accent-theme`).

`src/accent_theme/sources/models.py`:

```python
SourceKind = Literal["kde", "waywallen"]
SourceRequest = Literal["auto", "kde", "waywallen"]

@dataclass(frozen=True, slots=True)
class ThemeSource:
    kind: SourceKind
    reference: str
    preview: Path | None = None
    accent: str | None = None
```

`SourceError(RuntimeError)` con constructores:

- `invalid_source(value: str) -> SourceError`
- `invalid_config(path: Path, detail: str) -> SourceError`
- `missing_last_wallpaper(path: Path) -> SourceError`
- `missing_item(database: Path, wallpaper_id: str) -> SourceError`
- `invalid_preview(preview: Path, library_root: Path) -> SourceError`
- `missing_preview(path: Path) -> SourceError`
- `unreadable_database(path: Path, detail: str) -> SourceError`

`src/accent_theme/sources/resolver.py`:

```python
SOURCE_REQUESTS: Final[tuple[SourceRequest, ...]] = ("auto", "kde", "waywallen")

def resolve_source_kind(request: str, environ: Mapping[str, str]) -> SourceKind: ...
def resolve_source(request: str, paths: ThemePaths, environ: Mapping[str, str]) -> ThemeSource: ...
```

`src/accent_theme/sources/kde.py`:

```python
def read_kde_source(paths: ThemePaths, environ: Mapping[str, str]) -> ThemeSource: ...
```

`src/accent_theme/sources/waywallen.py`:

```python
def read_last_wallpaper(config_path: Path) -> str: ...
def resolve_preview_path(database_path: Path, wallpaper_id: str) -> Path: ...
def read_waywallen_source(paths: ThemePaths) -> ThemeSource: ...
```

SQL exacta para `resolve_preview_path`:

```sql
SELECT i.preview_path, l.path
FROM item AS i
JOIN library AS l ON l.id = i.library_id
WHERE i.id = ?
```

Conexión exacta: `sqlite3.connect(f"file:{quote(str(database_path))}?mode=ro", uri=True)`.

Validación exacta de preview:

- `preview_relative.is_absolute()` es error.
- `".." in preview_relative.parts` es error.
- `candidate = (library_root / preview_relative).resolve(strict=False)`.
- `root = library_root.resolve(strict=False)`.
- `candidate.is_relative_to(root)` es obligatorio.
- `candidate.is_file()` es obligatorio.

`src/accent_theme/matugen.py`:

```python
REQUIRED_IMAGE_ROLES: Final[tuple[str, ...]] = REQUIRED_ROLES + ("source_color",)

def parse_matugen_json(
    text: str,
    *,
    required_roles: tuple[str, ...] = REQUIRED_ROLES,
) -> MatugenTokens: ...

def invoke_matugen_image(
    binary: Path,
    image: Path,
    config: Path,
    *,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> MatugenTokens: ...
```

Comando exacto:

```python
[
    str(binary),
    "image",
    str(image),
    "-c",
    str(config),
    "-t",
    "scheme-fidelity",
    "-m",
    "dark",
    "-j",
    "hex",
    "--prefer",
    "saturation",
]
```

`src/accent_theme/accent.py`:

```python
class AccentError(RuntimeError):
    @classmethod
    def invalid_hex(cls, value: str) -> AccentError: ...

def accent_from_hex(value: str) -> Accent: ...
```

`src/accent_theme/state.py`:

```python
@dataclass(frozen=True, slots=True)
class ThemeState:
    source: SourceKind
    reference: str
    wallpaper_id: str | None
    source_color: str
    generated_at: str
    status: Literal["ok", "error"] = "ok"

def state_document(state: ThemeState) -> dict[str, object]: ...
def write_state(path: Path, state: ThemeState) -> None: ...
def read_state(path: Path) -> ThemeState | None: ...
```

JSON exacto:

```json
{
  "source": "waywallen",
  "reference": "27",
  "wallpaperId": "27",
  "sourceColor": "#ec1413",
  "generatedAt": "2026-11-23T20:00:00Z",
  "status": "ok"
}
```

`src/accent_theme/generation.py`:

```python
@dataclass(frozen=True, slots=True)
class GenerationResult:
    source: ThemeSource
    tokens: MatugenTokens
    source_color: str
    registrations: tuple[TemplateRegistration, ...]
    app_results: tuple[AppResult, ...]
    live_results: tuple[LiveResult, ...]
    state: ThemeState

def generate_once(
    paths: ThemePaths,
    environ: Mapping[str, str],
    source_request: str = "auto",
    *,
    generated_at: str | None = None,
) -> GenerationResult: ...
```

`src/accent_theme/watcher.py`:

```python
@dataclass(frozen=True, slots=True)
class WatcherPaths:
    kdeglobals: Path
    cache_path: Path
    lock_path: Path
    waywallen_config: Path | None = None
    waywallen_database: Path | None = None

@dataclass(frozen=True, slots=True)
class Watcher:
    paths: WatcherPaths
    environ: Mapping[str, str]
    source: SourceKind = "kde"
    generate_command: Sequence[str] = DEFAULT_GENERATE_COMMAND
    settle_seconds: float = SETTLE_SECONDS
    state: GenerationState = field(default_factory=GenerationState, compare=False)
```

- Mantener `current_accent`, `cached_accent`, `store_accent`, `accent_changed` como alias compatibles con KDE.
- Añadir:
  - `watched_paths() -> tuple[Path, ...]`
  - `inotify_command() -> list[str]`
  - `is_relevant(raw_path: str) -> bool`
  - `current_reference() -> str`
  - `cached_reference() -> str`
  - `store_reference(reference: str) -> None`
  - `reference_changed(reference: str) -> bool`
  - `handle_event(raw_path: str) -> str`
  - `check_once() -> str`
  - `generation_command() -> tuple[str, ...]`

Comando de generación exacto del watcher:

```python
("accent-theme", "generate", "--source", source)
```

`DEFAULT_GENERATE_COMMAND` se conserva por compatibilidad; el watcher usa `generation_command()`.

### `caparazon-shell`

`integration/bin/caparazon-wm.py`:

```python
@dataclass(frozen=True, slots=True)
class ThemeStatusPaths:
    home: Path
    cache_home: Path
    state_path: Path

def theme_status_paths(environ: Mapping[str, str]) -> ThemeStatusPaths: ...
def theme_status_payload(paths: ThemeStatusPaths) -> dict[str, object]: ...
```

Contrato de salida:

```json
{
  "available": true,
  "source": "waywallen",
  "reference": "27",
  "wallpaperId": "27",
  "sourceColor": "#ec1413",
  "generatedAt": "2026-11-23T20:00:00Z",
  "status": "ok"
}
```

Si no existe estado:

```json
{
  "available": false,
  "source": "",
  "reference": "",
  "wallpaperId": null,
  "sourceColor": "",
  "generatedAt": "",
  "status": "sin estado"
}
```

## File Structure

### `accent-theme`

Crear:

- `src/accent_theme/sources/__init__.py`
- `src/accent_theme/sources/models.py`
- `src/accent_theme/sources/kde.py`
- `src/accent_theme/sources/waywallen.py`
- `src/accent_theme/sources/resolver.py`
- `src/accent_theme/state.py`
- `src/accent_theme/generation.py`
- `templates/gtk3/colors.css`
- `templates/gtk4/colors.css`
- `templates/qt6ct/matugen.conf`
- `templates/kcolor/Matugen.colors`
- `templates/kvantum/matugen.kvconfig`
- `templates/kvantum/matugen.svg`
- `templates.d/gtk3.toml`
- `templates.d/gtk4.toml`
- `templates.d/qt6ct.toml`
- `templates.d/kcolor.toml`
- `templates.d/kvantum-config.toml`
- `templates.d/kvantum-svg.toml`
- `tests/test_sources.py`
- `tests/test_accent.py`
- `tests/test_matugen_image.py`
- `tests/test_state.py`
- `tests/test_generation.py`

Modificar:

- `src/accent_theme/paths.py`
- `src/accent_theme/accent.py`
- `src/accent_theme/matugen.py`
- `src/accent_theme/cli.py`
- `src/accent_theme/watcher.py`
- `install.sh`
- `systemd/accent-theme.service`
- `README.md`
- `tests/test_cli.py`
- `tests/test_watcher.py`
- `tests/test_install_contract.py`

### `caparazon-shell`

Eliminar:

- `integration/theme/app-theme/`
- `modules/secondmenu/AppThemePanel.qml`
- `tests/test_app_theme.py`
- `tests/test_app_theme_assets.py`
- `tests/test_app_theme_panel.py`

Crear:

- `tests/test_theme_status.py`

Modificar:

- `integration/bin/caparazon-wm.py`
- `install.sh`
- `modules/secondmenu/NiriConfigsPanel.qml`
- `README.md`
- `tests/test_niri_configs_panel.py`
- `tests/test_theme_install_contract.py`
- `tests/test_install_compositor_agnostic.py`

Fuera de repositorio, editar con `read`/`edit`:

- `/home/ezku/.config/niri/config.d/40-environment.kdl`
- `/home/ezku/.config/niri/config.d/50-startup.kdl`
- `/home/ezku/.config/systemd/user/accent-theme.service`

## Tasks

### Task 0: instalar `qt6ct` con permiso ya concedido

**Files:**

- Sistema PikaOS.

**Step 1: ejecutar instalación autorizada**

- Usar skill `pikaos-sys`.
- Comando exacto:

```bash
sudo env DEBIAN_FRONTEND=noninteractive apt -y install qt6ct
```

- No instalar ningún otro paquete.
- No usar PPAs Ubuntu.

**Step 2: verificar instalación**

- Comandos:

```bash
dpkg-query -W -f='${Status}\n' qt6ct
command -v qt6ct
systemctl --failed
```

- Esperado: estado `install complete`, ruta del binario y `systemctl --failed` sin fallos nuevos.
- No hacer comprobaciones visuales.

---

### Task 1: ampliar `ThemePaths` y crear resolvedor de fuentes

**Files:**

- Modify `accent-theme/src/accent_theme/paths.py`
- Create `accent-theme/src/accent_theme/sources/__init__.py`
- Create `accent-theme/src/accent_theme/sources/models.py`
- Create `accent-theme/src/accent_theme/sources/resolver.py`
- Create `accent-theme/tests/test_sources.py`

**Step 1: tests rojos**

- Añadir tests:
  - `test_paths_expose_kde_waywallen_and_state_paths`
  - `test_resolve_source_kind_auto_uses_waywallen_for_niri`
  - `test_resolve_source_kind_auto_uses_kde_for_non_niri_desktop_chain`
  - `test_resolve_source_kind_auto_uses_kde_without_desktop`
  - `test_resolve_source_kind_rejects_unknown_request`
  - `test_resolve_source_dispatches_to_waywallen_reader` (monkeypatch del reader; los readers reales llegan en Tasks 2 y 3)
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_sources.py
```

- Esperado: fallos por campos y módulos inexistentes.

**Step 2: implementar mínimo**

- Ampliar `ThemePaths` según Interfaces exactas.
- Crear `SourceKind`, `SourceRequest`, `ThemeSource`, `SourceError` y `SOURCE_REQUESTS`.
- Implementar `resolve_source_kind` con `XDG_CURRENT_DESKTOP` dividido por `:` y comparación insensible a mayúsculas.
- Implementar `resolve_source` delegando a `read_kde_source` o `read_waywallen_source`; en este task se pueden dejar ambos readers como stubs que levanten `NotImplementedError` y se completan en Tasks 2 y 3.
- Exportar desde `sources/__init__.py`.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_sources.py
./.venv/bin/ruff check src/accent_theme/paths.py src/accent_theme/sources tests/test_sources.py
./.venv/bin/basedpyright src/accent_theme/paths.py src/accent_theme/sources tests/test_sources.py
```

---

### Task 2: lector KDE y `accent_from_hex`

**Files:**

- Modify `accent-theme/src/accent_theme/accent.py`
- Create `accent-theme/src/accent_theme/sources/kde.py`
- Create `accent-theme/tests/test_accent.py`
- Modify `accent-theme/tests/test_sources.py`

**Step 1: tests rojos**

- Añadir:
  - `test_accent_from_hex_returns_expected_components`
  - `test_accent_from_hex_accepts_uppercase`
  - `test_accent_from_hex_rejects_invalid_values`
  - `test_read_kde_source_uses_accent_color`
  - `test_read_kde_source_falls_back_to_decorative_precolor`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_accent.py tests/test_sources.py
```

**Step 2: implementar mínimo**

- Añadir `AccentError.invalid_hex`.
- Añadir `accent_from_hex` validando `#RRGGBB` y normalizando a minúsculas.
- Implementar `read_kde_source` usando el helper existente de lectura de accent y devolviendo `ThemeSource(kind="kde", reference=hex, accent=hex, preview=None)`.
- No tocar `~/.config/kdeglobals` real en tests; usar `tmp_path`.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_accent.py tests/test_sources.py
./.venv/bin/ruff check src/accent_theme/accent.py src/accent_theme/sources/kde.py tests/test_accent.py tests/test_sources.py
./.venv/bin/basedpyright src/accent_theme/accent.py src/accent_theme/sources/kde.py tests/test_accent.py tests/test_sources.py
```

---

### Task 3: lector Waywallen y validación de DB en modo read-only

**Files:**

- Create `accent-theme/src/accent_theme/sources/waywallen.py`
- Modify `accent-theme/src/accent_theme/sources/resolver.py`
- Modify `accent-theme/tests/test_sources.py`

**Step 1: tests rojos**

- Añadir:
  - `test_read_last_wallpaper_prefers_global_section`
  - `test_read_last_wallpaper_falls_back_to_display_entries`
  - `test_read_last_wallpaper_rejects_missing_value`
  - `test_resolve_preview_path_uses_read_only_uri`
  - `test_resolve_preview_path_returns_relative_preview_inside_library`
  - `test_resolve_preview_path_rejects_absolute_preview`
  - `test_resolve_preview_path_rejects_parent_traversal`
  - `test_resolve_preview_path_rejects_missing_item`
  - `test_read_waywallen_source_returns_preview_and_id`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_sources.py
```

**Step 2: implementar mínimo**

- `read_last_wallpaper`: usar `tomllib`, priorizar `[global].last_wallpaper`, luego entradas `[display.*].last_wallpaper` ordenadas; valor vacío o ausente → `SourceError.missing_last_wallpaper`.
- `resolve_preview_path`:
  - Conectar con URI `mode=ro`.
  - Ejecutar la SQL exacta.
  - Validar preview según reglas exactas.
  - Nunca abrir la DB para escritura.
- `read_waywallen_source`: combinar config + DB y devolver `ThemeSource(kind="waywallen", reference=wallpaper_id, preview=preview, accent=None)`.
- Actualizar `resolver.py` para importar reader real.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_sources.py
./.venv/bin/ruff check src/accent_theme/sources tests/test_sources.py
./.venv/bin/basedpyright src/accent_theme/sources tests/test_sources.py
```

---

### Task 4: Matugen `image` con `source_color` obligatorio

**Files:**

- Modify `accent-theme/src/accent_theme/matugen.py`
- Create `accent-theme/tests/test_matugen_image.py`
- Modify `accent-theme/tests/test_cli.py`

**Step 1: tests rojos**

- Añadir:
  - `test_invoke_matugen_image_builds_exact_command`
  - `test_parse_matugen_json_requires_source_color_when_requested`
  - `test_parse_matugen_json_validates_source_color_hex`
  - `test_parse_matugen_json_default_roles_remains_backward_compatible`
- Ajustar el fake Matugen de `tests/test_cli.py` para que los tests de `image` incluyan `source_color`.
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_matugen_image.py tests/test_cli.py
```

**Step 2: implementar mínimo**

- Añadir `REQUIRED_IMAGE_ROLES`.
- Forma verificada de `source_color`: `colors.source_color.dark.color` contiene el hex; el parser lo valida desde `dark.color`, mientras las plantillas Matugen siguen usando `colors.source_color.dark.hex`.
- Añadir parámetro `required_roles` a `parse_matugen_json` con default actual.
- Implementar `invoke_matugen_image` con el comando exacto y el mismo parseo de errores de `invoke_matugen`.
- No cambiar el comportamiento de `invoke_matugen`.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_matugen_image.py tests/test_cli.py
./.venv/bin/ruff check src/accent_theme/matugen.py tests/test_matugen_image.py tests/test_cli.py
./.venv/bin/basedpyright src/accent_theme/matugen.py tests/test_matugen_image.py tests/test_cli.py
```

---

### Task 5: estado JSON atómico

**Files:**

- Create `accent-theme/src/accent_theme/state.py`
- Create `accent-theme/tests/test_state.py`

**Step 1: tests rojos**

- Añadir:
  - `test_state_document_uses_external_keys`
  - `test_write_state_creates_parent_and_json`
  - `test_read_state_roundtrip`
  - `test_read_state_returns_none_for_missing_file`
  - `test_read_state_returns_none_for_invalid_payload`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_state.py
```

**Step 2: implementar mínimo**

- Implementar `ThemeState`, `state_document`, `write_state`, `read_state`.
- `write_state` usa `atomic_write_json` existente.
- `read_state` valida tipos y valores; cualquier problema devuelve `None`.
- No escribir `error` en el JSON.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_state.py
./.venv/bin/ruff check src/accent_theme/state.py tests/test_state.py
./.venv/bin/basedpyright src/accent_theme/state.py tests/test_state.py
```

---

### Task 6: orquestación `generate_once` con publicación atómica

**Files:**

- Create `accent-theme/src/accent_theme/generation.py`
- Create `accent-theme/tests/test_generation.py`

**Step 1: tests rojos**

- Añadir:
  - `test_generate_once_kde_uses_color_and_existing_roles`
  - `test_generate_once_waywallen_uses_image_and_source_color`
  - `test_generate_once_waywallen_propagates_accent_to_integrations`
  - `test_generate_once_validates_all_staging_before_publishing`
  - `test_generate_once_does_not_publish_when_staging_missing`
  - `test_generate_once_does_not_write_state_on_failure`
  - `test_generate_once_writes_state_with_deterministic_timestamp`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_generation.py
```

**Step 2: implementar mínimo**

- `generate_once`:
  1. Resolver fuente.
  2. Obtener binario Matugen.
  3. Obtener descriptores con `rebuild_config(paths)`.
  4. Crear directorios de salida.
  5. Ejecutar `invoke_matugen_image` para Waywallen; para KDE ejecutar `invoke_matugen(binary, accent, paths.matugen_config)`.
  6. Recolectar staging de todos los descriptores y validar existencia antes de cualquier reemplazo.
  7. Parsear como JSON y validar objeto de strings únicamente los staging de descriptores con `saturation`; el resto se publica tal cual.
  8. Aplicar saturación en memoria y publicar cada salida.
  9. Borrar staging tras publicación.
  10. Ejecutar apps live con accent derivado de `source_color`.
  11. Escribir `ThemeState`.
- `source_color`:
  - KDE: `source.accent`.
  - Waywallen: `tokens["source_color"]`.
- `state.reference`:
  - KDE: hex normalizado.
  - Waywallen: `wallpaperId`.
- Si falta staging o JSON inválido: lanzar `CliError.missing_outputs` o error equivalente sin publicar y sin escribir estado.
- No duplicar lógica de publicación desde `cli.py`; moverla a `generation.py`.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_generation.py
./.venv/bin/ruff check src/accent_theme/generation.py tests/test_generation.py
./.venv/bin/basedpyright src/accent_theme/generation.py tests/test_generation.py
```

---

### Task 7: CLI `generate --source --once --watch` y `watch --source --once`

**Files:**

- Modify `accent-theme/src/accent_theme/cli.py`
- Modify `accent-theme/tests/test_cli.py`

**Step 1: tests rojos**

- Añadir:
  - `test_generate_accepts_source_option`
  - `test_generate_once_is_one_shot_and_accepts_flag`
  - `test_generate_watch_delegates_to_watcher`
  - `test_watch_accepts_source_option`
  - `test_watch_once_checks_once_and_exits`
  - `test_cli_rejects_invalid_source`
  - `test_cli_reports_source_error_cleanly`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_cli.py
```

**Step 2: implementar mínimo**

- Parsear con `argparse.Namespace` en lugar de patrones posicionales manuales.
- Contrato:

```text
accent-theme generate [--source SOURCE] [--once] [--watch]
accent-theme watch [--source SOURCE] [--once]
```

- `SOURCE` ∈ `auto`, `kde`, `waywallen`; default `auto`.
- `generate --source X` llama a `generate_once(paths, environ, X)`.
- `generate --once` es one-shot; no cambia el comportamiento de `generate` sin `--watch`.
- `generate --watch` delega a `watch --source X`.
- `watch` resuelve el tipo concreto con `resolve_source_kind`, nunca pasa `auto` al comando hijo.
- Incluir `SourceError` en el manejo de errores para salida limpia.
- Mantener `doctor`, `rebuild-config` y `register` sin cambios funcionales.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_cli.py
./.venv/bin/ruff check src/accent_theme/cli.py tests/test_cli.py
./.venv/bin/basedpyright src/accent_theme/cli.py tests/test_cli.py
```

---

### Task 8: watcher source-aware con una sola unidad

**Files:**

- Modify `accent-theme/src/accent_theme/watcher.py`
- Modify `accent-theme/src/accent_theme/cli.py`
- Modify `accent-theme/tests/test_watcher.py`

**Step 1: tests rojos**

- Añadir:
  - `test_watcher_paths_for_kde_remains_unchanged`
  - `test_watcher_paths_for_waywallen_uses_config_and_database`
  - `test_waywallen_inotify_watches_both_parent_directories`
  - `test_waywallen_ignores_unrelated_events`
  - `test_waywallen_reference_cache_is_separate_from_kde`
  - `test_watcher_generation_command_uses_concrete_source`
  - `test_watch_once_returns_after_single_check`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_watcher.py tests/test_cli.py
```

**Step 2: implementar mínimo**

- Ampliar `WatcherPaths` y `Watcher` según Interfaces exactas.
- KDE conserva caché `last-watch-accent`.
- Waywallen usa caché `last-watch-waywallen`.
- Lock compartido: `feeder.lock`.
- `handle_event` compara referencia actual con cache, guarda nueva referencia y conserva los estados actuales: `regenerated`, `unchanged`, `ignored`, `locked` o `failed`.
- `check_once` llama a `handle_event` con primer path vigilado y devuelve ese estado.
- CLI construye `WatcherPaths` según fuente concreta.
- No crear segundo servicio ni segundo watcher en paralelo.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_watcher.py tests/test_cli.py
./.venv/bin/ruff check src/accent_theme/watcher.py src/accent_theme/cli.py tests/test_watcher.py tests/test_cli.py
./.venv/bin/basedpyright src/accent_theme/watcher.py src/accent_theme/cli.py tests/test_watcher.py tests/test_cli.py
```

---

### Task 9: templates GTK3, GTK4, Qt6ct, KColorScheme y Kvantum

**Files:**

- Create los 6 templates y 6 descriptores listados en File Structure.
- Modify `accent-theme/src/accent_theme/registry.py` sólo si hace falta soporte de nuevos roles.
- Modify `accent-theme/install.sh`
- Modify `accent-theme/tests/test_install_contract.py`

**Step 1: tests rojos**

- Añadir:
  - `test_required_base_apps_include_gtk_qt6ct_kcolor_and_kvantum`
  - `test_new_descriptors_have_outputs_inside_home`
  - `test_new_templates_exist_and_use_matugen_placeholders`
  - `test_generated_config_includes_all_new_apps`
  - `test_qt6ct_descriptor_output_is_fixed`
  - `test_kcolor_descriptor_output_is_fixed`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_install_contract.py
```

**Step 2: preparar plantillas**

- Copiar `gtk3-colors.css.tmpl` → `templates/gtk3/colors.css`.
- Copiar `gtk4-colors.css.tmpl` → `templates/gtk4/colors.css`.
- Copiar `qt6ct-colors.conf.tmpl` → `templates/qt6ct/matugen.conf`.
- Copiar `kvantum.kvconfig.tmpl` → `templates/kvantum/matugen.kvconfig`.
- Copiar `kvantum.svg.tmpl` → `templates/kvantum/matugen.svg`.
- Crear `templates/kcolor/Matugen.colors` desde el archivo actual leído, sustituyendo cada hex por placeholder `{{colors.<role>.dark.hex}}` del rol Matugen equivalente.
- Placeholder syntax exacta: `{{colors.<role>.dark.hex}}`.
- Roles permitidos: los de `REQUIRED_ROLES` más `source_color` cuando corresponda.
- No tocar `~/.config/Kvantum/kvantum.kvconfig`.

**Step 3: descriptores exactos**

- `gtk3.toml`: app `gtk3`, input `~/.config/accent-theme/templates/gtk3/colors.css`, output `~/.config/gtk-3.0/colors.css`.
- `gtk4.toml`: app `gtk4`, input `~/.config/accent-theme/templates/gtk4/colors.css`, output `~/.config/gtk-4.0/colors.css`.
- `qt6ct.toml`: app `qt6ct`, input `~/.config/accent-theme/templates/qt6ct/matugen.conf`, output `~/.config/qt6ct/colors/matugen.conf`.
- `kcolor.toml`: app `kcolor`, input `~/.config/accent-theme/templates/kcolor/Matugen.colors`, output `~/.local/share/color-schemes/Matugen.colors`.
- `kvantum-config.toml`: app `kvantum-config`, input `~/.config/accent-theme/templates/kvantum/matugen.kvconfig`, output `~/.config/Kvantum/matugen/matugen.kvconfig`.
- `kvantum-svg.toml`: app `kvantum-svg`, input `~/.config/accent-theme/templates/kvantum/matugen.svg`, output `~/.config/Kvantum/matugen/matugen.svg`.

**Step 4: implementar mínimo**

- Ampliar `BASE_APPS` en `install.sh` con los seis nombres.
- Añadir `qt6ct` a `APT_PACKAGES` como paquete recomendado; no añadir a `REQUIRED_INSTALL_DEPS` para no romper tests aislados sin el binario.
- Regenerar config en tests mediante helper existente.
- No ejecutar `install.sh` contra HOME real.

**Step 5: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_install_contract.py
./.venv/bin/ruff check src/accent_theme/registry.py tests/test_install_contract.py
```

---

### Task 10: servicio y documentación de `accent-theme`

**Files:**

- Modify `accent-theme/systemd/accent-theme.service`
- Modify `accent-theme/install.sh`
- Modify `accent-theme/README.md`
- Modify `accent-theme/tests/test_install_contract.py`

**Step 1: tests rojos**

- Añadir:
  - `test_service_uses_watch_with_source_auto`
  - `test_service_passes_desktop_environment`
  - `test_generate_helper_uses_source_auto`
  - `test_readme_documents_sources_and_state`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_install_contract.py
```

**Step 2: implementar mínimo**

- `systemd/accent-theme.service`:
  - `Description=Genera y aplica temas derivados del acento o wallpaper`.
  - `PassEnvironment=XDG_CURRENT_DESKTOP XDG_MENU_PREFIX`.
  - `ExecStart=%h/.local/bin/accent-theme watch --source auto`.
  - No `Environment=XDG_CURRENT_DESKTOP=niri`.
- `install.sh`:
  - `generate_palette()` usa `"$WRAPPER_PATH" generate --source auto`.
  - Al instalar la unit, no deshabilitar ni borrar servicios de KDE.
- `README.md` documentar:
  - Fuentes `kde`, `waywallen`, `auto`.
  - `accent-theme generate --source auto`.
  - `accent-theme watch --source auto`.
  - `~/.cache/accent-theme/niri-state.json`.
  - Salidas GTK/Qt6/KColorScheme/Kvantum.
  - `qt6ct` como dependencia opcional recomendada en Niri.
  - Kvantum se escribe pero no se activa automáticamente.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_install_contract.py
./.venv/bin/ruff check tests/test_install_contract.py
```

---

### Task 11: retirar panel manual de Caparazón

**Files:**

- Delete `caparazon-shell/integration/theme/app-theme/`
- Delete `caparazon-shell/modules/secondmenu/AppThemePanel.qml`
- Delete `caparazon-shell/tests/test_app_theme.py`
- Delete `caparazon-shell/tests/test_app_theme_assets.py`
- Delete `caparazon-shell/tests/test_app_theme_panel.py`
- Modify `caparazon-shell/integration/bin/caparazon-wm.py`
- Modify `caparazon-shell/install.sh`
- Modify `caparazon-shell/modules/secondmenu/NiriConfigsPanel.qml`
- Modify `caparazon-shell/tests/test_niri_configs_panel.py`
- Modify `caparazon-shell/tests/test_theme_install_contract.py`
- Modify `caparazon-shell/tests/test_install_compositor_agnostic.py`
- Modify `caparazon-shell/README.md`

**Step 1: tests rojos**

- Reescribir tests para exigir:
  - `AppThemePanel.qml` no existe.
  - `NiriConfigsPanel.qml` no contiene sección `Tema`, componente `AppThemePanel` ni host de tema.
  - `caparazon-wm.py` no contiene comando `app-theme`.
  - `install.sh` no instala assets `app-theme` ni escribe `app-theme.json`.
  - README no recomienda `caparazon-wm app-theme`.
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_niri_configs_panel.py tests/test_theme_install_contract.py tests/test_install_compositor_agnostic.py
```

**Step 2: implementar mínimo**

- Quitar de `caparazon-wm.py`:
  - Constantes `APP_THEME_*`.
  - Dataclasses y helpers `AppTheme*`.
  - Función `load_app_theme_engine`.
  - Rama `app-theme` del dispatcher.
  - Imports `importlib`/`ModuleType` si quedan sin uso.
- Quitar de `install.sh`:
  - `APP_THEME_SOURCE_DIR`, `APP_THEME_CONFIG_DIR`.
  - `install_app_theme_assets`.
  - Llamada `install_app_theme_assets`.
  - Limpieza de `app-theme.json`.
- Quitar bloque `Tema` de `NiriConfigsPanel.qml`, dejando sólo iconos y cursor.
- Borrar directorio y tests viejos listados.
- Actualizar README.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_niri_configs_panel.py tests/test_theme_install_contract.py tests/test_install_compositor_agnostic.py
```

- No exigir `ruff`/`basedpyright` limpios sobre `caparazon-shell`: la deuda preexistente está documentada en Baseline.
- La compuerta de este task son los tests; los chequeos acotados a archivos nuevos se hacen en Task 12 y Task 14.

---

### Task 12: comando `caparazon-wm theme status`

**Files:**

- Modify `caparazon-shell/integration/bin/caparazon-wm.py`
- Modify `caparazon-shell/README.md`
- Create `caparazon-shell/tests/test_theme_status.py`

**Step 1: tests rojos**

- Añadir:
  - `test_theme_status_reads_accent_theme_state`
  - `test_theme_status_without_state_reports_unavailable`
  - `test_theme_status_ignores_invalid_state`
  - `test_theme_status_is_read_only`
  - `test_theme_status_rejects_extra_arguments`
- Ejecutar:

```bash
./.venv/bin/python -m pytest -q tests/test_theme_status.py
```

**Step 2: implementar mínimo**

- Añadir `ThemeStatusPaths` y `theme_status_paths(environ)`.
- Ruta exacta: `XDG_CACHE_HOME/accent-theme/niri-state.json`, con fallback a `HOME/.cache/accent-theme/niri-state.json`.
- `theme_status_payload` valida tipos y devuelve payloads exactos descritos en Interfaces exactas.
- Registrar `theme status` en el dispatcher.
- No escribir archivos.
- Documentar en README reemplazando la sección manual.

**Step 3: verificación**

```bash
./.venv/bin/python -m pytest -q tests/test_theme_status.py tests/test_theme_install_contract.py
./.venv/bin/python -m py_compile integration/bin/caparazon-wm.py
./.venv/bin/ruff check tests/test_theme_status.py
./.venv/bin/basedpyright tests/test_theme_status.py
```

- No exigir `ruff`/`basedpyright` limpios sobre `integration/bin/caparazon-wm.py`: su deuda preexistente está documentada en Baseline.
- `py_compile` verifica sintaxis del ejecutable modificado sin mezclar diagnósticos preexistentes.

---

### Task 13: entorno Qt y servicio en Niri

**Files:**

- Modify `/home/ezku/.config/niri/config.d/40-environment.kdl`
- Modify `/home/ezku/.config/niri/config.d/50-startup.kdl`
- Modify `/home/ezku/.config/systemd/user/accent-theme.service` con `read`/`edit`, sin ejecutar `install.sh` contra HOME real.

**Step 1: inspección previa**

- Leer los tres archivos y confirmar líneas actuales antes de editar.
- Unit instalada actual: `Environment=PATH=...`, `ExecStart=%h/.local/bin/accent-theme watch`, `Description=Genera la paleta global de tema desde AccentColor de KDE`.

**Step 2: editar `40-environment.kdl`**

- La sintaxis real es un bloque `environment { ... }` con claves desnudas, no `environment CLAVE "valor"`.
- Mantener el bloque existente y dentro de él cambiar el comentario y la línea de Qt:

```kdl
    // Qt theming en Niri: qt6ct lee ~/.config/qt6ct/colors/matugen.conf.
    QT_QPA_PLATFORMTHEME "qt6ct"
    QT_QPA_PLATFORMTHEME_QT6 "qt6ct"
```

- No añadir `QT_STYLE_OVERRIDE`, `QT_QPA_PLATFORMTHEME=kvantum` ni variables Qt globales fuera de Niri.

**Step 3: editar `50-startup.kdl`**

- La sintaxis real es `spawn-at-startup "bash" "-c" "<comando>"`, no un comando desnudo.
- Reemplazar la línea actual:

```kdl
spawn-at-startup "bash" "-c" "systemctl --user import-environment XDG_MENU_PREFIX && kbuildsycoca6"
```

por:

```kdl
spawn-at-startup "bash" "-c" "systemctl --user import-environment XDG_CURRENT_DESKTOP XDG_MENU_PREFIX && kbuildsycoca6"
```

- Añadir inmediatamente después:

```kdl
spawn-at-startup "bash" "-c" "systemctl --user try-restart accent-theme.service"
```

- No deshabilitar ni enmascarar el servicio.

**Step 4: sincronizar la unit instalada**

- Editar `/home/ezku/.config/systemd/user/accent-theme.service` para que contenga:

```ini
[Unit]
Description=Genera y aplica temas derivados del acento o wallpaper
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
PassEnvironment=XDG_CURRENT_DESKTOP XDG_MENU_PREFIX
ExecStart=%h/.local/bin/accent-theme watch --source auto
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
```

- No ejecutar `install.sh`.
- Tras editar la unit:

```bash
systemctl --user daemon-reload
```

**Step 5: verificación**

- Leer los tres archivos tras edición.
- Verificar unit instalada:

```bash
systemctl --user cat accent-theme.service
systemctl --user show -p PassEnvironment --value accent-theme.service
systemctl --failed
```

- Esperado: `watch --source auto`, `PassEnvironment` con `XDG_CURRENT_DESKTOP XDG_MENU_PREFIX`, sin fallos nuevos.
- No mover mouse ni hacer comprobaciones visuales.

---

### Task 14: verificación final de ambos repos

**Files:**

- Ninguno.

**Step 1: suites completas**

```bash
./.venv/bin/python -m pytest -q
```

- Ejecutar en `/home/ezku/.local/share/accent-theme/source`.
- Ejecutar en `/home/ezku/Projects/caparazon-shell`.
- Esperado: todas pasan; se conserva el skip preexistente de `power-profiles-daemon`.

**Step 2: lint y tipos en archivos tocados**

En `accent-theme`:

```bash
./.venv/bin/ruff check src tests
./.venv/bin/basedpyright src/accent_theme/paths.py src/accent_theme/accent.py src/accent_theme/matugen.py src/accent_theme/cli.py src/accent_theme/watcher.py src/accent_theme/registry.py src/accent_theme/sources src/accent_theme/state.py src/accent_theme/generation.py tests/test_cli.py tests/test_watcher.py tests/test_install_contract.py tests/test_sources.py tests/test_accent.py tests/test_matugen_image.py tests/test_state.py tests/test_generation.py
```

- Esperado: `ruff` limpio; `basedpyright` limpio en ese subconjunto, aunque `src/accent_theme` completo conserva `29 errors, 3 warnings` preexistentes.

En `caparazon-shell`:

```bash
./.venv/bin/python -m py_compile integration/bin/caparazon-wm.py
./.venv/bin/ruff check tests/test_theme_status.py
./.venv/bin/basedpyright tests/test_theme_status.py
```

- Esperado: compilación correcta y archivo nuevo limpio.
- No exigir `ruff`/`basedpyright` limpios sobre `caparazon-wm.py` ni sobre la suite completa: su deuda preexistente está documentada en Baseline.

**Step 3: smoke de CLI sin HOME real**

- Usar `HOME=$(mktemp -d)` y `XDG_*` temporales para:
  - `accent-theme generate --source kde --once`.
  - `caparazon-wm theme status`.
- No ejecutar `install.sh` contra HOME real.
- No ejecutar comandos git.

**Step 4: verificación del sistema**

```bash
systemctl --user is-active accent-theme.service
systemctl --failed
command -v qt6ct
dpkg-query -W -f='${Status}\n' qt6ct
```

- No comprobaciones visuales sin permiso.

## Review Focus

- `read_last_wallpaper` prioriza `[global]`, fallback ordenado por display, sin aceptar valores vacíos.
- DB Waywallen se abre sólo en `mode=ro`; SQL con parámetro `?`, nunca interpolación.
- `preview_path` relativo, sin `..`, dentro de `library_root`, existente.
- Matugen Waywallen usa exactamente `image ... --prefer saturation` y exige `source_color`.
- Matugen KDE conserva `color`, roles anteriores y no exige `source_color`.
- Publicación atómica: validar todos los staging antes de reemplazar; si falta uno, no publicar nada.
- Estado no se escribe si falla generación; `status` siempre `ok` en archivo escrito.
- Modo `waywallen` no lee ni escribe `kdeglobals`, `kbuildsycoca6` ni configuración KDE.
- Watcher único, caché por fuente, lock compartido, sin segundo servicio.
- `auto` bajo Niri pasa fuente concreta al comando hijo; no depende de env heredado en el hijo.
- `PassEnvironment` + `try-restart` resuelven servicio ya corriente sin fijar `niri` en la unit.
- Niri usa `qt6ct`; Plasma/KDE no recibe `QT_QPA_PLATFORMTHEME`.
- Caparazón no conserva panel manual ni comando `app-theme`; `theme status` es de sólo lectura.
- Descriptores nuevos apuntan sólo a rutas bajo HOME; Kvantum se escribe pero no se activa.
- No hay comandos git en pasos de verificación ni commits.
- No se instala nada salvo `qt6ct` autorizado.
- No se ejecuta `install.sh` contra HOME real.
- No se hacen comprobaciones visuales ni se mueve el mouse.

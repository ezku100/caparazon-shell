# Tema manual de apps (GTK/Qt) en Niri Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task in the current session. No usar subagent-driven ni delegar a subagentes sin autorización explícita del usuario. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir un subcomando `caparazon-wm app-theme` y una pestaña `Tema` en `Niri configs` para elegir manualmente uno de los 17 tokens de la paleta activa y regenerar themes de GTK/Qt/apps con matugen sin tocar KDE ni la shell.

**Architecture:** La CLI amplía el único puente de sistema existente: lee `style.json` y la paleta cacheada, calcula el hex del token, usa los módulos Python de `accent-theme` para renderizar un config propio, invoca matugen, publica outputs con `staging -> os.replace` y llama a integraciones con un `Accent` derivado del hex. QML sólo ejecuta la CLI con `Process`. El instalador copia plantillas/descriptores propios a `~/.config/caparazon/app-theme` también en niri, sin registrarlos en `accent-theme`.

**Tech Stack:** Python 3.11, pytest, ruff, basedpyright, bash, QML/Quickshell, matugen 4.2, módulos de `accent-theme`.

**Spec:** `docs/superpowers/specs/2026-11-23-app-theme-niri-manual-design.md`

## Global Constraints

- Responder en español.
- `"CLI como única puerta al sistema"`.
- `"TDD estricto"`.
- `"sin commits sin petición explícita"`.
- `"No ejecutar comandos de git de lectura/escritura (git status, git diff, git log...)"`.
- `"No instalar nada de nada (ni siquiera paquetes pequeños como curl o jq). Si hace falta algo así, pedir permiso primero."`.
- `"No delegar a subagentes/categorías con modelos premium... Solo se vale delegar si el usuario lo pide explícito en ese mensaje."`.
- `"recuerda que no debemos afectar el funcionamiento de la shell con kde"`.
- `"DALE VAMOS CON EL QUE RECOMIENDAS SOLO RECUERDA ESTO NO DEBE DAÑAR NI INTERRUMPIR LO QUE YA SE TIENE EN KDE CON LA SHELL"`.
- `"bro estoy usando mi computadora si quieres comprobaciones visuales pidemelas porque interrumpes el trabajo al quitarme el mause y eso"`.
- No ejecutar comprobaciones visuales ni reiniciar la shell sin permiso explícito.
- No ejecutar `install.sh` contra el HOME real durante esta tarea; el instalador se prueba sólo con `HOME`/XDG aislados.
- No modificar `~/.config/caparazon/style.json`, `~/.cache/caparazon/colors*.json`, `~/.config/kdeglobals` ni `~/.config/accent-theme/matugen.toml`.
- No registrar plantillas nuevas en `accent-theme` ni llamar a `accent-theme generate`/`read_kde_accent`.

## Review Focus

- Un token desconocido o un hex inválido podría dejar archivos publicados a medias: cubierto por `test_app_theme_set_rejects_unknown_token_without_writes` y `test_app_theme_set_rejects_invalid_hex_without_writes` en Task 3.
- El panel podría funcionar en Plasma y pisar el tema de KDE: cubierto por `test_app_theme_set_refuses_in_kwin_without_writes` en Task 3 y por el gate `detect_compositor() == "niri"` en Task 3.
- Un descriptor futuro de `accent-theme` podría escribir fuera de la lista permitida: cubierto por `test_app_theme_config_ignores_unknown_app_descriptors` en Task 2 y `test_app_theme_set_publishes_only_allowed_outputs` en Task 4.
- La generación podría reescribir la paleta de la shell o el config de KDE: cubierto por `test_app_theme_set_preserves_shell_and_kde_files` en Task 4 y `test_app_theme_config_never_touches_accent_theme_config` en Task 2.
- El panel podría escribir archivos directamente o no reflejar `engineAvailable: false`: cubierto por `test_app_theme_panel_uses_cli_only` y `test_app_theme_panel_loads_state` en Task 6.

---

### Task 1: Contrato de estado y mapeo de tokens en la CLI

**Files:**
- Create: `tests/test_app_theme.py`
- Modify: `integration/bin/caparazon-wm.py`
- Modify: `tests/test_app_theme.py` (helper compartido por_tasks posteriores)

**Interfaces:**
- Consumes: patrón `_run_cli`/`_load_cli_module` de `tests/test_caparazon_wm.py`; `integration/theme/required-tokens.txt`; `~/.config/caparazon/style.json`; `~/.cache/caparazon/colors*.json`.
- Produces:
  - `APP_THEME_TOKENS: Final[tuple[tuple[str, str], ...]]` con 17 pares `(token shell, role matugen)` en el orden de `required-tokens.txt`.
  - `APP_THEME_STYLES: Final[tuple[str, ...]] = ("material", "oled", "perla")`.
  - `APP_THEME_HEX_RE: Final[re.Pattern[str]] = re.compile(r"^#[0-9a-f]{6}$")`.
  - `AppThemePaths` (`frozen=True, slots=True`) con `home`, `config_home`, `cache_home`, `data_home`, `style_file`, `palette_file`, `selection_file`, `templates_dir`, `descriptors_dir`, `matugen_config`, `engine_source`.
  - `app_theme_paths(environ: Mapping[str, str]) -> AppThemePaths`.
  - `app_theme_read_style(path: Path) -> str` (inválido o ausente ⇒ `"material"`).
  - `app_theme_read_palette(path: Path) -> tuple[dict[str, str], str]`; segundo valor es mensaje de error o `""`.
  - `app_theme_read_selection(path: Path) -> tuple[str, str]`.
  - `AppThemeToken` y `AppThemeState` (`frozen=True, slots=True`) con `to_json()`.
  - `app_theme_state(environ: Mapping[str, str] | None = None) -> AppThemeState`.
  - `app_theme_engine_available(paths: AppThemePaths, environ: Mapping[str, str]) -> bool`: stub que devuelve `False`; Task 2 lo reemplaza.
  - `app-theme` en docstring, usage y `main()` sin args ⇒ imprime JSON; opción inválida ⇒ exit 2.
  - En tests: `APP_THEME_CLI`, `_run_app_theme_cli(...)`, `_app_theme_env(...)`, `_write_style(...)`, `_write_app_theme_palette(...)`, `_tree_snapshot(...)`, `_tree_snapshot_many(...)`.

- [x] **Step 1: Write the failing tests**

Crear `tests/test_app_theme.py`. Primero los imports y helpers base:

```python
import json
import subprocess
from pathlib import Path

from test_caparazon_wm import CLI, REPOSITORY_ROOT, _load_cli_module, _run_cli, _write_exec
```

Luego estos tests:

```python
def test_app_theme_state_lists_17_tokens_for_active_style(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path, style="oled")
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["style"] == "oled"
    assert [item["name"] for item in payload["tokens"]] == [
        "surface", "surfaceContainerLowest", "surfaceContainerLow",
        "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest",
        "fgSurface", "fgSurfaceVariant", "outline", "outlineVariant",
        "primary", "fgPrimary", "secondary", "tertiary", "error",
        "errorContainer", "fgErrorContainer",
    ]
    assert next(item for item in payload["tokens"] if item["name"] == "tertiary")["hex"] == "#4ccfdf"
```

```python
def test_app_theme_state_follows_style_json(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path, style="oled")
    _write_style(tmp_path / "home" / ".config" / "caparazon" / "style.json", "perla")
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    payload = json.loads(result.stdout)
    assert payload["style"] == "perla"
```

```python
def test_app_theme_state_uses_material_when_style_missing(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path, style="oled")
    (tmp_path / "home" / ".config" / "caparazon" / "style.json").unlink()
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    payload = json.loads(result.stdout)
    assert payload["style"] == "material"
```

```python
def test_app_theme_state_reports_invalid_palette(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    palette = tmp_path / "home" / ".cache" / "caparazon" / "colors-oled.json"
    palette.write_text('{"primary": "rojo"}', encoding="utf-8")
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    payload = json.loads(result.stdout)
    assert payload["error"]
    assert len(payload["tokens"]) == 17
    assert all(item["hex"] == "" for item in payload["tokens"])
```

```python
def test_app_theme_state_reads_selection(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    (home / ".config" / "caparazon" / "app-theme.json").write_text(
        '{"token":"tertiary"}\n', encoding="utf-8"
    )
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    payload = json.loads(result.stdout)
    assert payload["selected"] == "tertiary"
```

```python
def test_app_theme_cli_prints_state_json(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    assert set(json.loads(result.stdout)) == {
        "style", "selected", "engineAvailable", "tokens", "error"
    }
```

```python
def test_app_theme_cli_rejects_unknown_option(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme", "--bogus"], env_extra=environ)
    assert result.returncode == 2
    assert "app-theme [--set" in result.stderr
```

```python
def test_app_theme_token_order_matches_required_tokens_file() -> None:
    required = (REPOSITORY_ROOT / "integration" / "theme" / "required-tokens.txt")
    expected = [line.strip() for line in required.read_text(encoding="utf-8").splitlines() if line.strip()]
    cli = _load_cli_module()
    assert [name for name, _ in cli.APP_THEME_TOKENS] == expected
```

Helpers requeridos:
- `APP_THEME_CLI` es alias de `CLI`.
- `_run_app_theme_cli(args: list[str], *, env_extra: dict[str, str] | None = None, fake_bin: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]` delega en `_run_cli(args, env_extra=env_extra, fake_bin=fake_bin)`; cada test pasa `args` ya iniciado con `"app-theme"`.
- `_app_theme_env(tmp_path, *, style="oled")` crea `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `NIRI_SOCKET`, escribe `style.json` y las tres paletas, y devuelve `(env, home)`.
- `_write_style(path, style)` escribe `{"style": style, "auto": false}`.
- `_write_app_theme_palette(home, style, **overrides)` deriva los 17 tokens de un diccionario base válido y aplica overrides. La base usa `primary = "#ff908d"`, `tertiary = "#4ccfdf"` y los otros 15 tokens con `"#808080"`.
- `_tree_snapshot(root: Path) -> dict[str, str]` acepta archivo o directorio y guarda `SHA256` de cada archivo; se usa en Tasks 2-4.
- `_tree_snapshot_many(roots: object) -> dict[str, str]` combina `_tree_snapshot()` de una lista o tupla de rutas.

- [x] **Step 2: Run tests to verify they fail**

Run: `./.venv/bin/python -m pytest tests/test_app_theme.py -q`
Expected: FAIL por `ModuleNotFoundError` del módulo de tests o por `app-theme` desconocido.

- [x] **Step 3: Implement state and token mapping**

En `integration/bin/caparazon-wm.py`:
- Agregar imports `Mapping` (bajo `TYPE_CHECKING` si se quiere) y `ModuleType`; `json`, `os`, `re`, `Path`, `Any`, `Final` ya existen.
- Definir las constantes y dataclasses de Interfaces. `AppThemeToken` tiene `name: str` y `hex: str`; `AppThemeState` tiene `style: str`, `selected: str`, `engineAvailable: bool`, `tokens: tuple[AppThemeToken, ...]` y `error: str`, con `to_json()` que usa esas claves exactas.
- `APP_THEME_TOKENS` usa este mapping exacto, en orden de `required-tokens.txt`: `surface→surface`, `surfaceContainerLowest→surface_container_lowest`, `surfaceContainerLow→surface_container_low`, `surfaceContainer→surface_container`, `surfaceContainerHigh→surface_container_high`, `surfaceContainerHighest→surface_container_highest`, `fgSurface→on_surface`, `fgSurfaceVariant→on_surface_variant`, `outline→outline`, `outlineVariant→outline_variant`, `primary→primary`, `fgPrimary→on_primary`, `secondary→secondary`, `tertiary→tertiary`, `error→error`, `errorContainer→error_container`, `fgErrorContainer→on_error_container`.
- Implementar `app_theme_paths()` con XDG (convertir cada base a `Path` antes de usar `/`):
  - `config_home = Path(environ.get("XDG_CONFIG_HOME", home / ".config"))`
  - `cache_home = Path(environ.get("XDG_CACHE_HOME", home / ".cache"))`
  - `data_home = Path(environ.get("XDG_DATA_HOME", home / ".local/share"))`
  - `style_file = config_home / "caparazon" / "style.json"`
  - `palette_file` según estilo: `colors.json`, `colors-oled.json`, `colors-perla.json` dentro de `cache_home / "caparazon"`.
  - `selection_file = config_home / "caparazon" / "app-theme.json"`
  - `templates_dir = config_home / "caparazon" / "app-theme" / "templates"`
  - `descriptors_dir = config_home / "caparazon" / "app-theme" / "templates.d"`
  - `matugen_config = cache_home / "caparazon" / "app-theme" / "matugen.toml"`
  - `engine_source = Path(environ.get("ACCENT_THEME_SOURCE", data_home / "accent-theme" / "source"))`
- `app_theme_read_palette()` valida los 17 nombres y `APP_THEME_HEX_RE`; devuelve hex en minúsculas y error acumulado que contenga la palabra `paleta`.
- `app_theme_state(environ=None)` construye `env = dict(os.environ if environ is None else environ)`, usa `paths = app_theme_paths(env)` y `app_theme_engine_available(paths, env)` (stub `False` por ahora); construye los 17 `AppThemeToken` con hex `""` si hay error y serializa con claves exactas del test.
- Registrar `app-theme` en docstring y `main()` con el patrón de `icon-theme`; usar textos exactos:
  - `uso: caparazon-wm app-theme [--set <token>]` para opción inválida o `--help`.
  - `uso: caparazon-wm app-theme --set <token>` para `--set` sin valor.
  Ambos escriben a `sys.stderr` y devuelven `2`.

- [x] **Step 4: Run tests to verify they pass**

Run: `./.venv/bin/python -m pytest tests/test_app_theme.py -q`
Expected: PASS (8 tests).

- [x] **Step 5: Lint new test file**

Run: `./.venv/bin/python -m ruff check tests/test_app_theme.py`
Expected: limpio.

---

### Task 2: Carga del motor, descriptores y config propio de matugen

**Files:**
- Modify: `tests/test_app_theme.py`
- Modify: `integration/bin/caparazon-wm.py`

**Interfaces:**
- Consumes: `AppThemePaths`, `app_theme_state()`, `app_theme_engine_available()` stub de Task 1.
- Produces:
  - `AppThemeError(RuntimeError)`.
  - `AppThemeEngine` (`frozen=True, slots=True`) con `accent`, `matugen`, `registry`, `apps`, `live` como módulos.
  - `APP_THEME_OWN_OUTPUTS: Final[dict[str, str]]` con:
    - `caparazon-app-gtk3` → `.config/gtk-3.0/colors.css`
    - `caparazon-app-gtk4` → `.config/gtk-4.0/colors.css`
    - `caparazon-app-qt5ct` → `.config/qt5ct/colors/matugen.conf`
    - `caparazon-app-qt6ct` → `.config/qt6ct/colors/matugen.conf`
    - `caparazon-app-kvantum-config` → `.config/Kvantum/matugen/matugen.kvconfig`
    - `caparazon-app-kvantum-svg` → `.config/Kvantum/matugen/matugen.svg`
  - `APP_THEME_APP_OUTPUTS: Final[dict[str, str]]` con los 8 descriptores permitidos y sus rutas relativas: `cava-matugen` → `.cache/matugen-cava-snippet`, `ghostty-matugen` → `.config/ghostty/theme`, `heroic-matugen` → `.config/heroic/themes/dinamico.css`, `kate-matugen` → `.local/share/org.kde.syntax-highlighting/themes/dinamico.theme`, `kitty-matugen` → `.config/kitty/theme.conf`, `konsole-matugen` → `.local/share/konsole/Dinamico.colorscheme`, `steam-matugen` → `.local/share/Steam/millennium/themes/Material-Theme/css/main/colors/matugen.css`, `zen-matugen` → `.cache/matugen-zen-kde-accent.css`.
  - `load_app_theme_engine(paths: AppThemePaths) -> AppThemeEngine`.
  - `app_theme_engine_available(paths, environ) -> bool` reemplaza al stub.
  - `app_theme_load_registrations(engine: AppThemeEngine, paths: AppThemePaths) -> tuple[Any, ...]`.
  - `app_theme_render_config(registrations: tuple[Any, ...], paths: AppThemePaths, engine: AppThemeEngine) -> str`.
  - `app_theme_apply(token: str, environ: Mapping[str, str] | None = None) -> int` provisional, sin validación ni publicación: carga motor, carga registros, renderiza config y devuelve `0`. Task 3 añade validación; Task 4 completa el pipeline.
  - En tests: `_write_fake_engine(root: Path) -> dict[str, str]` y `_write_app_theme_assets(home: Path) -> None`.

- [x] **Step 1: Write the failing tests**

Agregar a `tests/test_app_theme.py`:

```python
def test_fake_app_theme_engine_is_available(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    assert json.loads(result.stdout)["engineAvailable"] is True
```

```python
def test_app_theme_engine_unavailable_without_source(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    assert json.loads(result.stdout)["engineAvailable"] is False
```

```python
def test_app_theme_config_uses_own_templates(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    config = (home / ".cache" / "caparazon" / "app-theme" / "matugen.toml").read_text(encoding="utf-8")
    assert "[templates.caparazon-app-gtk3]" in config
    assert str(home / ".config" / "gtk-3.0" / "colors.staging.css") in config
    assert "[templates.cava-matugen]" in config
```

```python
def test_app_theme_config_excludes_shell_templates(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    config = (home / ".cache" / "caparazon" / "app-theme" / "matugen.toml").read_text(encoding="utf-8")
    assert "caparazon-shell" not in config
    assert "colors.staging.json" not in config
```

```python
def test_app_theme_config_ignores_unknown_app_descriptors(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    rogue = home / ".config" / "accent-theme" / "templates.d" / "rogue.toml"
    rogue.write_text(
        f'name = "rogue-matugen"\ninput_path = "{home}/x"\noutput_path = "{home}/.config/kdeglobals"\n',
        encoding="utf-8",
    )
    _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    config = (home / ".cache" / "caparazon" / "app-theme" / "matugen.toml").read_text(encoding="utf-8")
    assert "rogue-matugen" not in config
    assert "kdeglobals" not in config
```

```python
def test_app_theme_config_never_touches_accent_theme_config(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    foreign = home / ".config" / "accent-theme" / "matugen.toml"
    foreign.write_text("config original\n", encoding="utf-8")
    before = _tree_snapshot(foreign)
    _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert _tree_snapshot(foreign) == before
```

Helper `_write_fake_engine(root)` define `source_root = root / ".local" / "share" / "accent-theme" / "source"` y `fake_binary = root.parent / "fake-matugen"`; crea `source_root / "src" / "accent_theme/"` con:
- `__init__.py` vacío.
- `accent.py`: `@dataclass(frozen=True, slots=True) class Accent(red: int, green: int, blue: int)`.
- `matugen.py`: `find_matugen(environ) -> Path | None` que devuelve `Path(environ["MATUGEN"])` si existe; `invoke_matugen(binary, accent, config)` que escribe una línea JSON `{"accent": accent, "config": str(config)}` en `APP_THEME_TEST_LOG` si esa variable existe, lee `output_path` del config, escribe cada staging con `seed=<accent>\n` y devuelve tokens cuyo `app_environment()` es `{"MATUGEN_ACCENT": accent}`.
- `registry.py`: réplica mínima de `parse_descriptor`, `expand_home_path`, `TemplateRegistration` con `staging_path`, y `render_matugen_config` con el mismo formato del motor real (`[config]`, `version_check = false`, `caching = false` y bloques ordenados por nombre con `input_path`/`output_path` en JSON).
- `apps/__init__.py`: `AppPaths.from_environment`, `AppResult`, `apply_app_integrations(paths, accent, palette)` que escribe `{"kind": "apps", "rgb": [accent.red, accent.green, accent.blue], "MATUGEN_ACCENT": palette["MATUGEN_ACCENT"]}` en el log y devuelve 4 resultados.
- `live/__init__.py`: `LivePaths.from_environment`, `LiveResult`, `apply_live_integrations(paths, accent, environ)` que escribe `{"kind": "live", "accent": accent}` en el log y devuelve 5 resultados.
- Crear `fake_binary` con `_write_exec(fake_binary, "#!/bin/sh\nexit 0\n")` y devolver `{"ACCENT_THEME_SOURCE": str(source_root), "MATUGEN": str(fake_binary)}`.

Helper `_write_app_theme_assets(home)` debe crear:
- 6 inputs bajo `home/.config/caparazon/app-theme/templates/` con nombres `gtk3-colors.css.tmpl`, `gtk4-colors.css.tmpl`, `qt5ct-colors.conf.tmpl`, `qt6ct-colors.conf.tmpl`, `kvantum.kvconfig.tmpl` y `kvantum.svg.tmpl`.
- 6 descriptores bajo `home/.config/caparazon/app-theme/templates.d/` con `name`, `input_path` apuntando al input propio y `output_path` de `APP_THEME_OWN_OUTPUTS`.
- 8 inputs bajo `home/.config/accent-theme/templates/<nombre>.tmpl` y 8 descriptores bajo `home/.config/accent-theme/templates.d/<nombre>.toml` con los nombres y `output_path` de `APP_THEME_APP_OUTPUTS`.

- [x] **Step 2: Run tests to verify they fail**

Run: `./.venv/bin/python -m pytest tests/test_app_theme.py -q`
Expected: FAIL porque `app-theme --set` aún no existe.

- [x] **Step 3: Implement engine loader and registration filtering**

En `integration/bin/caparazon-wm.py`:
- `load_app_theme_engine()` inserta `paths.engine_source / "src"` en `sys.path[0]`, limpia entradas `accent_theme*` de `sys.modules`, usa `importlib.invalidate_caches()` e `importlib.import_module`.
- `app_theme_engine_available()` envuelve carga + `find_matugen(environ)` en `try/except (AppThemeError, ImportError, OSError, AttributeError)`.
- `app_theme_load_registrations()`:
  - Carga descriptores propios desde `paths.descriptors_dir.glob("*.toml")` y requiere nombre en `APP_THEME_OWN_OUTPUTS`, output exactamente `home / rel`, input existente y dentro de `paths.templates_dir`.
  - Carga descriptores externos desde `config_home/accent-theme/templates.d/*.toml`; ignora cualquier nombre que no esté en `APP_THEME_APP_OUTPUTS` (esto excluye `caparazon-shell*`); valida output exacto e input existente.
  - Usa `parse_descriptor`, `expand_home_path` y `TemplateRegistration` del motor; rechaza duplicados con `AppThemeError`.
- `app_theme_render_config()` usa `engine.registry.render_matugen_config(registrations)` y `_atomic_write_text(paths.matugen_config, ...)`.
- Definir `app_theme_apply()` provisional: construye `paths` desde `dict(os.environ if environ is None else environ)`, carga engine, carga registros, llama a `app_theme_render_config()` y devuelve `0`. No valida token ni compositor; no invoca matugen, no publica salidas, no escribe selection.
- En `main()`, la rama `app-theme --set <valor>` pasa `rest[1]` a `app_theme_apply()` y devuelve su código; `--help` y `--set` sin valor ya se manejan en Task 1 con `app-theme [--set <token>]` y `app-theme --set <token>`.
- Conectar `app_theme_state()` con la implementación real de `app_theme_engine_available()`.

- [x] **Step 4: Run tests to verify they pass**

Run: `./.venv/bin/python -m pytest tests/test_app_theme.py -q`
Expected: PASS (14 tests).

- [x] **Step 5: Lint**

Run: `./.venv/bin/python -m ruff check tests/test_app_theme.py`
Expected: limpio.

---

### Task 3: Validación previa y gate de compositor

**Files:**
- Modify: `tests/test_app_theme.py`
- Modify: `integration/bin/caparazon-wm.py`

**Interfaces:**
- Consumes: `AppThemePaths`, `app_theme_read_palette()`, `app_theme_read_selection()`, `load_app_theme_engine()`, `app_theme_load_registrations()`.
- Produces:
  - `app_theme_apply(token: str, environ: Mapping[str, str] | None = None) -> int` con validación y failed-fast; Task 4 completa el pipeline.
  - En tests: `FAKE_BUSCTL_KWIN_OK`, `_assert_tree_unchanged(root, before)`.

- [x] **Step 1: Write the failing tests**

Agregar helpers:

```python
FAKE_BUSCTL_KWIN_OK = """#!/bin/sh
# activeOutputName o cualquier call a org.kde.KWin
echo 's "DP-1"'
exit 0
"""


def _assert_tree_unchanged(root: Path, before: dict[str, str]) -> None:
    assert _tree_snapshot(root) == before
```

Luego estos tests:

```python
def test_app_theme_set_refuses_in_kwin_without_writes(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.pop("NIRI_SOCKET", None)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    before = _tree_snapshot(home)
    result = _run_app_theme_cli(
        ["app-theme", "--set", "primary"],
        env_extra=environ,
        fake_bin={"busctl": FAKE_BUSCTL_KWIN_OK},
    )
    assert result.returncode == 1
    assert "sólo niri" in result.stderr
    _assert_tree_unchanged(home, before)
```

```python
def test_app_theme_set_rejects_unknown_token_without_writes(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    before = _tree_snapshot(home)
    result = _run_app_theme_cli(["app-theme", "--set", "cactus"], env_extra=environ)
    assert result.returncode == 1
    assert "token inválido" in result.stderr
    _assert_tree_unchanged(home, before)
```

```python
def test_app_theme_set_rejects_invalid_hex_without_writes(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    palette = home / ".cache" / "caparazon" / "colors-oled.json"
    palette.write_text('{"primary":"#zzzzzz"}', encoding="utf-8")
    before = _tree_snapshot(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 1
    assert "paleta" in result.stderr
    _assert_tree_unchanged(home, before)
```

```python
def test_app_theme_set_refuses_when_engine_missing_without_writes(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    _write_app_theme_assets(home)
    before = _tree_snapshot(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 1
    assert "motor" in result.stderr
    _assert_tree_unchanged(home, before)
```

```python
def test_app_theme_help_reports_usage(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme", "--help"], env_extra=environ)
    assert result.returncode == 2
    assert "app-theme [--set <token>]" in result.stderr
```

```python
def test_app_theme_set_without_value_reports_usage(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme", "--set"], env_extra=environ)
    assert result.returncode == 2
    assert "app-theme --set <token>" in result.stderr
```

- [x] **Step 2: Run tests to verify they fail**

Run: `./.venv/bin/python -m pytest tests/test_app_theme.py -q`
Expected: FAIL en los 4 tests de validación; los 2 tests de uso ya pueden pasar.

- [x] **Step 3: Implement validation path**

En `integration/bin/caparazon-wm.py`:
- Reordenar `app_theme_apply()` de Task 2: primero validar, y sólo después ejecutar la carga de motor, registros y render de config. No debe escribirse nada —ni config de matugen— antes de validar.
- `app_theme_apply()` usa `env = dict(os.environ if environ is None else environ)` y `paths = app_theme_paths(env)`.
- Orden exacto de validación: `detect_compositor() == "niri"`; `token in dict(APP_THEME_TOKENS)`; `palette, error = app_theme_read_palette(paths.palette_file)` sin error; `hex_value = palette[token]` y `APP_THEME_HEX_RE.fullmatch(hex_value)`; `app_theme_engine_available(paths, env)`.
- Mensajes exactos en `sys.stderr`, todos con prefijo `app-theme: ` y exit 1:
  - compositor: `app-theme: sólo niri`.
  - token: `app-theme: token inválido: <token>`.
  - paleta/hex: `app-theme: paleta inválida: <detalle>`.
  - motor: `app-theme: motor accent-theme no disponible`.
- `main()` pasa `rest[1]` a `app_theme_apply()` y devuelve su código.
- Tras validar, conservar la carga de motor, `app_theme_load_registrations()` y render de config de Task 2; todavía no publicar salidas ni selection.

- [x] **Step 4: Run tests to verify they pass**

Run: `./.venv/bin/python -m pytest tests/test_app_theme.py -q`
Expected: PASS (20 tests).

- [x] **Step 5: Lint**

Run: `./.venv/bin/python -m ruff check tests/test_app_theme.py`
Expected: limpio.

---

### Task 4: Pipeline de aplicación, publicación atómica e integraciones

**Files:**
- Modify: `tests/test_app_theme.py`
- Modify: `integration/bin/caparazon-wm.py`

**Interfaces:**
- Consumes: `app_theme_apply()` validado; `app_theme_load_registrations()`, `app_theme_render_config()`; helpers de fake engine.
- Produces:
  - `app_theme_accent(hex_value: str, engine: AppThemeEngine) -> Any`.
  - `app_theme_publish_outputs(registrations: tuple[Any, ...]) -> tuple[str, ...]`.
  - `app_theme_serialize_results(items: object) -> list[dict[str, str]]`.
  - `app_theme_apply()` completo imprime JSON `{style, token, hex, outputs, apps, live}`.
  - En tests: `_read_log(path) -> list[dict[str, object]]`.

- [x] **Step 1: Write the failing tests**

Agregar helper:

```python
def _read_log(path: Path) -> list[dict[str, object]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
```

Luego estos tests:

```python
def test_app_theme_set_invokes_matugen_with_selected_seed(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    log = tmp_path / "matugen.log"
    environ["APP_THEME_TEST_LOG"] = str(log)
    result = _run_app_theme_cli(["app-theme", "--set", "tertiary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    entry = _read_log(log)[0]
    assert entry["accent"] == "#4ccfdf"
    assert entry["config"] == str(home / ".cache" / "caparazon" / "app-theme" / "matugen.toml")
```

```python
def test_app_theme_set_uses_own_matugen_config(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    generated = (home / ".cache" / "caparazon" / "app-theme" / "matugen.toml").read_text(encoding="utf-8")
    assert generated.startswith("[config]\n")
    assert str(home / ".config" / "accent-theme" / "matugen.toml") not in generated
```

```python
def test_app_theme_set_publishes_only_allowed_outputs(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    payload = json.loads(result.stdout)
    outputs = set(payload["outputs"])
    assert str(home / ".config" / "gtk-3.0" / "colors.css") in outputs
    assert str(home / ".config" / "kitty" / "theme.conf") in outputs
    assert str(home / ".config" / "kdeglobals") not in outputs
    assert (home / ".config" / "gtk-3.0" / "colors.css").is_file()
```

```python
def test_app_theme_set_cleans_staging_files(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    staging = [path for path in home.rglob("*.staging*") if path.is_file()]
    assert staging == []
```

```python
def test_app_theme_set_calls_app_integrations_with_explicit_accent(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    log = tmp_path / "integrations.log"
    environ["APP_THEME_TEST_LOG"] = str(log)
    result = _run_app_theme_cli(["app-theme", "--set", "tertiary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    entries = _read_log(log)
    app_entry = next(item for item in entries if item["kind"] == "apps")
    assert app_entry["rgb"] == [76, 207, 223]
    assert app_entry["MATUGEN_ACCENT"] == "#4ccfdf"
```

```python
def test_app_theme_set_calls_live_integrations_with_explicit_accent(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    log = tmp_path / "integrations.log"
    environ["APP_THEME_TEST_LOG"] = str(log)
    result = _run_app_theme_cli(["app-theme", "--set", "tertiary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    entries = _read_log(log)
    live_entry = next(item for item in entries if item["kind"] == "live")
    assert live_entry["accent"] == "#4ccfdf"
```

```python
def test_app_theme_set_writes_selection_and_result_json(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    payload = json.loads(result.stdout)
    assert set(payload) == {"style", "token", "hex", "outputs", "apps", "live"}
    assert payload["token"] == "primary"
    assert payload["hex"] == "#ff908d"
    selection = (home / ".config" / "caparazon" / "app-theme.json").read_text(encoding="utf-8")
    assert json.loads(selection) == {"token": "primary"}
    assert list((home / ".config" / "caparazon").glob("app-theme.json.*")) == []
```

```python
def test_app_theme_set_preserves_shell_and_kde_files(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    protected = [
        home / ".config" / "caparazon" / "style.json",
        home / ".cache" / "caparazon" / "colors.json",
        home / ".cache" / "caparazon" / "colors-oled.json",
        home / ".cache" / "caparazon" / "colors-perla.json",
        home / ".config" / "kdeglobals",
        home / ".config" / "accent-theme" / "matugen.toml",
    ]
    before = _tree_snapshot_many(protected)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    assert _tree_snapshot_many(protected) == before
```

- [x] **Step 2: Run tests to verify they fail**

Run: `./.venv/bin/python -m pytest tests/test_app_theme.py -q`
Expected: FAIL porque `--set` aún no publica ni imprime resultado.

- [x] **Step 3: Implement full apply pipeline**

En `integration/bin/caparazon-wm.py`:
- Completar `app_theme_apply()` tras la validación de Task 3, reutilizando `env`, `paths` y `hex_value` ya calculados (no validar dos veces):
  1. `engine = load_app_theme_engine(paths)`.
  2. `binary = engine.matugen.find_matugen(dict(env))`; si falta, error.
  3. `registrations = app_theme_load_registrations(engine, paths)`.
  4. `app_theme_render_config(...)`.
  5. `tokens = engine.matugen.invoke_matugen(binary, hex_value, paths.matugen_config)`.
  6. `outputs = app_theme_publish_outputs(registrations)`.
  7. `accent = app_theme_accent(hex_value, engine)`.
  8. `app_paths = engine.apps.AppPaths.from_environment(dict(env))`; `apps = engine.apps.apply_app_integrations(app_paths, accent, tokens.app_environment())`.
  9. `live_paths = engine.live.LivePaths.from_environment(dict(env))`; `live = engine.live.apply_live_integrations(live_paths, hex_value, dict(env))`.
  10. Escribir selection atómicamente con `_atomic_write_text(paths.selection_file, json.dumps({"token": token}) + "\n")`.
  11. Imprimir JSON con `ensure_ascii=False`.
- `app_theme_publish_outputs()` comprueba primero que todos los staging existan; luego `mkdir(parents=True, exist_ok=True)`, `os.replace(staging, final)` y limpieza de staging en `finally`.
- Si matugen o integraciones fallan, no escribir selection y limpiar staging; devolver 1 con mensaje.
- Serializar resultados con `app/status/detail` de cada objeto del motor.

- [x] **Step 4: Run tests to verify they pass**

Run: `./.venv/bin/python -m pytest tests/test_app_theme.py -q`
Expected: PASS (28 tests).

- [x] **Step 5: Lint**

Run: `./.venv/bin/python -m ruff check tests/test_app_theme.py`
Expected: limpio.

---

### Task 5: Plantillas/descriptores versionados e integración del instalador

**Files:**
- Create: `integration/theme/app-theme/templates/gtk3-colors.css.tmpl`
- Create: `integration/theme/app-theme/templates/gtk4-colors.css.tmpl`
- Create: `integration/theme/app-theme/templates/qt5ct-colors.conf.tmpl`
- Create: `integration/theme/app-theme/templates/qt6ct-colors.conf.tmpl`
- Create: `integration/theme/app-theme/templates/kvantum.kvconfig.tmpl`
- Create: `integration/theme/app-theme/templates/kvantum.svg.tmpl`
- Create: `integration/theme/app-theme/templates.d/caparazon-app-gtk3.toml`
- Create: `integration/theme/app-theme/templates.d/caparazon-app-gtk4.toml`
- Create: `integration/theme/app-theme/templates.d/caparazon-app-qt5ct.toml`
- Create: `integration/theme/app-theme/templates.d/caparazon-app-qt6ct.toml`
- Create: `integration/theme/app-theme/templates.d/caparazon-app-kvantum-config.toml`
- Create: `integration/theme/app-theme/templates.d/caparazon-app-kvantum-svg.toml`
- Modify: `install.sh`
- Create: `tests/test_app_theme_assets.py`
- Modify: `tests/test_install_compositor_agnostic.py`

**Interfaces:**
- Consumes: constantes `APP_THEME_OWN_OUTPUTS` de Task 2; helper `isolated_environment()` de `tests/test_install_compositor_agnostic.py`.
- Produces:
  - 6 plantillas con placeholders `{{colors.<role>.dark.hex}}` derivadas de los archivos generados actuales.
  - 6 descriptores propios con `name`, `input_path = "~/.config/caparazon/app-theme/templates/<archivo>"` y `output_path` de `APP_THEME_OWN_OUTPUTS`.
  - `install_app_theme_assets()` en `install.sh`, llamada desde `install_theme()` antes del branch KDE.
  - `uninstall` elimina `$CONFIG_HOME/caparazon/app-theme` y `$CONFIG_HOME/caparazon/app-theme.json`.

- [x] **Step 1: Write the failing tests**

Crear `tests/test_app_theme_assets.py` con estos imports:

```python
import re

from test_caparazon_wm import REPOSITORY_ROOT
```

Luego estos tests:

```python
def test_app_theme_template_and_descriptor_files_exist() -> None:
    root = REPOSITORY_ROOT / "integration" / "theme" / "app-theme"
    for name in (
        "gtk3-colors.css.tmpl", "gtk4-colors.css.tmpl",
        "qt5ct-colors.conf.tmpl", "qt6ct-colors.conf.tmpl",
        "kvantum.kvconfig.tmpl", "kvantum.svg.tmpl",
    ):
        assert (root / "templates" / name).is_file()
    for name in (
        "caparazon-app-gtk3.toml", "caparazon-app-gtk4.toml",
        "caparazon-app-qt5ct.toml", "caparazon-app-qt6ct.toml",
        "caparazon-app-kvantum-config.toml", "caparazon-app-kvantum-svg.toml",
    ):
        assert (root / "templates.d" / name).is_file()
```

```python
def test_app_theme_descriptors_match_expected_outputs() -> None:
    descriptors = (REPOSITORY_ROOT / "integration" / "theme" / "app-theme" / "templates.d").glob("*.toml")
    parsed = {}
    for path in descriptors:
        values = dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines() if "=" in line)
        parsed[values["name"].strip(' "')] = values["output_path"].strip(' "')
    assert parsed == {
        "caparazon-app-gtk3": "~/.config/gtk-3.0/colors.css",
        "caparazon-app-gtk4": "~/.config/gtk-4.0/colors.css",
        "caparazon-app-qt5ct": "~/.config/qt5ct/colors/matugen.conf",
        "caparazon-app-qt6ct": "~/.config/qt6ct/colors/matugen.conf",
        "caparazon-app-kvantum-config": "~/.config/Kvantum/matugen/matugen.kvconfig",
        "caparazon-app-kvantum-svg": "~/.config/Kvantum/matugen/matugen.svg",
    }
```

```python
def test_app_theme_templates_use_placeholders() -> None:
    root = REPOSITORY_ROOT / "integration" / "theme" / "app-theme" / "templates"
    for template in root.glob("*.tmpl"):
        text = template.read_text(encoding="utf-8")
        assert re.search(r"\{\{colors\.[a-z_]+\.dark\.hex\}\}", text)
        assert re.search(r"#[0-9a-fA-F]{6}", text) is None
```

En `tests/test_install_compositor_agnostic.py` agregar:

```python
def test_installer_copies_app_theme_assets_on_niri(tmp_path: Path) -> None:
    environ = isolated_environment(tmp_path, desktop="niri")
    result = run_installer(environ, answers="y\n")
    assert result.returncode == 0, result.stderr
    target = tmp_path / "home" / ".config" / "caparazon" / "app-theme"
    assert (target / "templates" / "gtk3-colors.css.tmpl").is_file()
    assert (target / "templates.d" / "caparazon-app-gtk3.toml").is_file()
```

```python
def test_installer_does_not_register_app_theme_templates(tmp_path: Path) -> None:
    environ = isolated_environment(tmp_path, desktop="niri")
    result = run_installer(environ, answers="y\n")
    assert result.returncode == 0, result.stderr
    descriptors = tmp_path / "home" / ".config" / "accent-theme" / "templates.d"
    assert not descriptors.exists()
    assert "accent-theme" in result.stdout
```

- [x] **Step 2: Run tests to verify they fail**

Run: `./.venv/bin/python -m pytest tests/test_app_theme_assets.py tests/test_install_compositor_agnostic.py -q`
Expected: FAIL por archivos faltantes y por no copiar assets en niri.

- [x] **Step 3: Create real templates and descriptors**

Derivar cada plantilla de los archivos generados actuales (`~/.config/gtk-3.0/colors.css`, `~/.config/gtk-4.0/colors.css`, `~/.config/qt5ct/colors/matugen.conf`, `~/.config/qt6ct/colors/matugen.conf`, `~/.config/Kvantum/matugen/matugen.kvconfig`, `~/.config/Kvantum/matugen/matugen.svg`): conservar nombres de variables, orden y estructura; reemplazar cada literal por el placeholder del role matugen correspondiente. Mapping obligatorio:

| Role matugen | Placeholder |
|---|---|
| `surface` | `{{colors.surface.dark.hex}}` |
| `surface_container_lowest` | `{{colors.surface_container_lowest.dark.hex}}` |
| `surface_container_low` | `{{colors.surface_container_low.dark.hex}}` |
| `surface_container` | `{{colors.surface_container.dark.hex}}` |
| `surface_container_high` | `{{colors.surface_container_high.dark.hex}}` |
| `surface_container_highest` | `{{colors.surface_container_highest.dark.hex}}` |
| `on_surface` | `{{colors.on_surface.dark.hex}}` |
| `on_surface_variant` | `{{colors.on_surface_variant.dark.hex}}` |
| `outline` | `{{colors.outline.dark.hex}}` |
| `outline_variant` | `{{colors.outline_variant.dark.hex}}` |
| `primary` | `{{colors.primary.dark.hex}}` |
| `on_primary` | `{{colors.on_primary.dark.hex}}` |
| `secondary` | `{{colors.secondary.dark.hex}}` |
| `tertiary` | `{{colors.tertiary.dark.hex}}` |
| `error` | `{{colors.error.dark.hex}}` |
| `error_container` | `{{colors.error_container.dark.hex}}` |
| `on_error_container` | `{{colors.on_error_container.dark.hex}}` |

Reglas de semántica: fondos/ventanas → `surface*`; textos foreground → `on_surface*`; bordes → `outline*`; selección/hover/link/accent → `primary`/`on_primary`; acento secundario → `secondary`/`tertiary`; errores → `error*`; success/warning se mapean al role de acento menos saturado disponible sin introducir colores nuevos. Si un literal es ambiguo, copiar el role del archivo generado actual con el mismo significado.

- [x] **Step 4: Implement installer asset copy**

En `install.sh`:
- Agregar variables `APP_THEME_SOURCE_DIR="$REPO/integration/theme/app-theme"` y `APP_THEME_CONFIG_DIR="$CONFIG_HOME/caparazon/app-theme"`.
- Definir `install_app_theme_assets()` con `mkdir -p "$APP_THEME_CONFIG_DIR/templates" "$APP_THEME_CONFIG_DIR/templates.d"` y `cp -f` de los dos directorios fuente.
- Llamar `install_app_theme_assets()` al inicio de `install_theme()`, antes de `if ! is_kde_session`.
- En `remove_caparazon_theme()` agregar `rm -rf "$APP_THEME_CONFIG_DIR"` y `rm -f "$CONFIG_HOME/caparazon/app-theme.json"`.
- No tocar `register_caparazon_theme()` ni `~/.config/accent-theme/templates.d`.

- [x] **Step 5: Run tests to verify they pass**

Run: `./.venv/bin/python -m pytest tests/test_app_theme_assets.py tests/test_install_compositor_agnostic.py -q`
Expected: PASS.

- [x] **Step 6: Lint tests and check installer syntax**

Run: `./.venv/bin/python -m ruff check tests/test_app_theme_assets.py tests/test_install_compositor_agnostic.py && bash -n install.sh`
Expected: limpio.

---

### Task 6: Panel QML en Niri configs

**Files:**
- Create: `modules/secondmenu/AppThemePanel.qml`
- Modify: `modules/secondmenu/NiriConfigsPanel.qml`
- Modify: `tests/test_niri_configs_panel.py`
- Create: `tests/test_app_theme_panel.py`

**Interfaces:**
- Consumes: JSON de `caparazon-wm app-theme` de Task 1; `--set` de Task 4; patrón de `IconThemePanel.qml`.
- Produces: pestaña `tema`, componente `appThemeComponent`, panel `AppThemePanel.qml` que sólo usa `Process`.

- [x] **Step 1: Write the failing tests**

En `tests/test_niri_configs_panel.py` agregar:

```python
def test_the_panel_registers_the_theme_section() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '{ key: "tema", label: "Tema" }' in contents
```

```python
def test_the_panel_resolves_the_theme_component() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert 'if (key === "tema")' in contents
    assert "return appThemeComponent" in contents
    assert "AppThemePanel" in contents
```

Crear `tests/test_app_theme_panel.py` con imports y constante:

```python
from test_caparazon_wm import REPOSITORY_ROOT

PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "AppThemePanel.qml"
```

Luego estos tests:

```python
def test_app_theme_panel_uses_cli_only() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert 'command: ["caparazon-wm", "app-theme"]' in contents
    assert 'command: ["caparazon-wm", "app-theme", "--set", root.pendingToken]' in contents
    assert "FileIO" not in contents
    assert "Write" not in contents
    assert ".config" not in contents
```

```python
def test_app_theme_panel_loads_state() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "Component.onCompleted: load.running = true" in contents
    assert "root.tokens = Array.isArray(data.tokens) ? data.tokens : []" in contents
    assert "root.engineAvailable = data.engineAvailable === true" in contents
    assert "Motor accent-theme no disponible" in contents
```

```python
def test_app_theme_panel_applies_selected_token() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "function choose(token)" in contents
    assert "root.pendingToken = token" in contents
    assert "apply.running = true" in contents
    assert "root.selected = root.pendingToken" in contents
```

- [x] **Step 2: Run tests to verify they fail**

Run: `./.venv/bin/python -m pytest tests/test_niri_configs_panel.py tests/test_app_theme_panel.py -q`
Expected: FAIL por pestaña y panel ausentes.

- [x] **Step 3: Implement QML panel and tab**

En `NiriConfigsPanel.qml`:
- Agregar `{ key: "tema", label: "Tema" }` a `sections`.
- En `componentFor(key)`, devolver `appThemeComponent` para `"tema"`.
- Agregar `Component { id: appThemeComponent; AppThemePanel { anchors.fill: parent } }`.

Crear `AppThemePanel.qml` siguiendo `IconThemePanel.qml`:
- Properties: `tokens`, `selected`, `pendingToken`, `engineAvailable`, `errorMessage`, `noticeMessage`, `applying`.
- `Process id: load` con `command: ["caparazon-wm", "app-theme"]` y `StdioCollector` que parsea JSON y llena properties.
- `Process id: apply` con `command: ["caparazon-wm", "app-theme", "--set", root.pendingToken]`, stderr a `errorMessage`, y en `onExited` actualiza `selected`/notice sólo con exit 0.
- `Grid`/`Repeater` de 17 swatches: `modelData.name` como etiqueta, `modelData.hex` como color de Rectangle, borde cuando `modelData.name === root.selected`, `MouseArea.onClicked: root.choose(modelData.name)`.
- Footer con error/notice; si `engineAvailable === false`, mostrar "Motor accent-theme no disponible" y deshabilitar clicks.

- [x] **Step 4: Run tests to verify they pass**

Run: `./.venv/bin/python -m pytest tests/test_niri_configs_panel.py tests/test_app_theme_panel.py -q`
Expected: PASS.

- [x] **Step 5: Lint**

Run: `./.venv/bin/python -m ruff check tests/test_niri_configs_panel.py tests/test_app_theme_panel.py`
Expected: limpio.

---

### Task 7: Documentación de uso manual y watcher futuro

**Files:**
- Modify: `README.md`
- Modify: `tests/test_app_theme_assets.py`

**Interfaces:**
- Consumes: flujo de Task 1 y Task 4.
- Produces: sección README con comandos CLI y nota de reutilización futura.

- [x] **Step 1: Write the failing tests**

Agregar a `tests/test_app_theme_assets.py`:

```python
def test_readme_documents_manual_app_theme() -> None:
    text = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
    assert "Tema de aplicaciones en niri" in text
    assert "Niri configs" in text
    assert "GTK" in text and "Qt" in text
```

```python
def test_readme_documents_cli_contract() -> None:
    text = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
    assert "caparazon-wm app-theme" in text
    assert "caparazon-wm app-theme --set" in text
```

```python
def test_readme_documents_future_watcher() -> None:
    text = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
    assert "vigilante de wallpaper" in text
    assert "mismo comando" in text
```

- [x] **Step 2: Run tests to verify they fail**

Run: `./.venv/bin/python -m pytest tests/test_app_theme_assets.py -q`
Expected: FAIL por sección ausente.

- [x] **Step 3: Update README**

Agregar una sección `#### Tema de aplicaciones en niri` después de `#### Tema de iconos`:
- Explicar que en niri no hay Plasma que repinte GTK/Qt y que el submenú **Niri configs → Tema** aplica uno de los 17 tokens de la paleta activa.
- Mostrar:

```bash
caparazon-wm app-theme
caparazon-wm app-theme --set tertiary
```

- Aclarar que no se escribe `style.json`, `colors*.json`, `kdeglobals` ni el config de `accent-theme`, y que en Plasma no se toca nada porque el comando se niega fuera de niri.
- Cerrar con: el futuro vigilante de wallpaper en niri debe llamar a este mismo comando, no duplicar la lógica.

- [x] **Step 4: Run tests to verify they pass**

Run: `./.venv/bin/python -m pytest tests/test_app_theme_assets.py -q`
Expected: PASS.

- [x] **Step 5: Lint**

Run: `./.venv/bin/python -m ruff check tests/test_app_theme_assets.py`
Expected: limpio.

---

### Task 8: Verificación completa sin efectos en el sistema

**Files:** ninguno.

**Interfaces:**
- Consumes: todos los cambios anteriores.
- Produces: evidencia de suite limpia y sintaxis del instalador, sin ejecutar comandos git ni instalación real.

- [x] **Step 1: Full pytest suite**

Run: `./.venv/bin/python -m pytest -q`
Expected: `846 passed, 1 skipped` (805 previos + 41 nuevos confirmados por conteo de `def test_` en el plan).
Nota: resultado real `847 passed, 1 skipped`; el plan estimó 846.

- [x] **Step 2: Lint all touched tests**

Run: `./.venv/bin/python -m ruff check tests/test_app_theme.py tests/test_app_theme_assets.py tests/test_app_theme_panel.py tests/test_niri_configs_panel.py tests/test_install_compositor_agnostic.py`
Expected: limpio.

- [x] **Step 3: Type check configured Python targets**

Run: `./.venv/bin/python -m basedpyright`
Expected: 0 errors.
Nota: ejecutado; archivos nuevos del feature 0 errores (19 warnings). El repo tenía 170 errores/96 warnings preexistentes fuera de este cambio; no se corrigieron por directiva de no tocar deuda ajena. Detalle en el ledger SDD.

- [x] **Step 4: Installer syntax**

Run: `bash -n install.sh`
Expected: salida vacía, exit 0.

- [x] **Step 5: No commit and no live checks**

No ejecutar `git add`, `git commit`, `git push`, `install.sh` contra el HOME real, `pkill`, reinicios de shell, ni comprobaciones visuales. No instalar paquetes.

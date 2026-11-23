# Plan: tema de iconos en niri y categoría dinámica "Iconos"

Fecha: 2026-11-21 · Diseño: `docs/superpowers/specs/2026-11-21-iconos-niri-design.md`
(comprobado con el usuario: categoría en el submenú, sólo en niri; Papirus-Dark
por defecto; la shell se reinicia sola al aplicar).

## Objetivo

Que en niri la shell tenga iconos (del sistema y del menú) con un tema real —
Papirus-Dark por defecto — y que exista una categoría "Iconos" en el rail del
`SecondMenu` para ver y cambiar ese tema, visible **sólo** en niri.

## Reglas de la casa

- TDD estricto: test rojo antes de cada cambio de comportamiento.
- El CLI es la única puerta al sistema: el QML no escribe ficheros de
  configuración por su cuenta.
- Español en código, comentarios y documentación.
- **Sin commits** hasta que el usuario lo pida explícitamente.

## Ficheros

### Nuevos

| Fichero | Responsabilidad |
| --- | --- |
| `modules/icons/CompositorService.qml` | Singleton: compositor de la sesión, una consulta por proceso |
| `modules/secondmenu/IconThemePanel.qml` | Panel nuevo: lista de temas, marca el activo, aplica el elegido |

### Modificados

| Fichero | Cambio |
| --- | --- |
| `integration/bin/caparazon-wm.py` | Subcomando `icon-theme` (consulta y `--set`) |
| `modules/icons/IconTheme.js` | `defaultIconTheme(text)`: lee `Name=` de `[Icon Theme]` |
| `modules/icons/IconThemeWatcher.qml` | Vigila `~/.icons/default` y reinicia cuando cambia |
| `modules/icons/qmldir` | Declara el singleton `CompositorService` |
| `modules/secondmenu/SecondMenu.qml` | Categoría dinámica "Iconos" (sólo niri) y su panel |
| `install.sh` | Default `Papirus-Dark` en niri y aviso si falta el paquete |
| `README.md` | Requisito `papirus-icon-theme` y sección del tema de iconos |
| `tests/test_caparazon_wm.py` | Contrato del subcomando `icon-theme` |
| `tests/support/icon_theme_harness.js` | Escenarios de `defaultIconTheme()` |
| `tests/test_icon_theme.py` | Casos de `defaultIconTheme()` |
| `tests/test_icon_theme_niri.py` | Contrato QML (nuevo) |
| `tests/test_install_compositor_agnostic.py` | Default y aviso del instalador |

## Contrato del CLI (queda fijado aquí; no se decide durante la implementación)

`caparazon-wm icon-theme` → JSON por stdout:

```json
{"current": "Papirus-Dark", "themes": ["Adwaita", "Papirus"],
 "previews": {"Papirus": "/usr/share/icons/Papirus/Papirus.png"},
 "default": "Papirus-Dark", "configured": true}
```

- `current`: lo que dice `~/.icons/default`; si no hay fichero, el default.
- `configured`: si el fichero existe (distingue "elegido" de "puesto por defecto").
- `themes`: directorios con `index.theme`, ordenados.
- `previews`: miniatura por tema (ruta absoluta o "" si no hay). *Es una
  extensión del contrato del diseño: el diseño los pedía como cadenas; las
  miniaturas en JSON evitan que el QML lance un proceso por tema.*
- `default`: siempre `Papirus-Dark`.

`caparazon-wm icon-theme --set <tema>` → valida que el tema esté instalado y
escribe `~/.icons/default` de forma atómica. Código 0; tema desconocido → 1
con mensaje en stderr; falta el argumento → 2.

Las rutas de los temas salen de `XDG_DATA_DIRS` (por defecto
`/usr/local/share:/usr/share`), `XDG_DATA_HOME` (por defecto `~/.local/share`)
y `~/.icons`: cada una aporta su subdirectorio `icons`, salvo `~/.icons`, que
es el directorio en sí. Los tests aíslan el entorno con esas variables, así que
no dependen de lo que haya instalado la máquina.

## Tarea 1 — CLI: consulta y aplicación del tema

Ficheros: `integration/bin/caparazon-wm.py`, `tests/test_caparazon_wm.py`.

1. **Test rojo** en `tests/test_caparazon_wm.py`, con `_run_cli(..., env_extra=...)`
   y un `HOME`/`XDG_DATA_DIRS`/`XDG_DATA_HOME` temporales:
   - `test_icon_theme_lists_the_installed_themes`: un directorio temporal con
     `icons/Papirus-Dark/index.theme` → `themes` lo incluye.
   - `test_icon_theme_reports_the_default_without_a_default_file`: `current` es
     `Papirus-Dark` y `configured` es `false`.
   - `test_icon_theme_reads_the_configured_theme`: con `~/.icons/default` que
     contiene `[Icon Theme]\nName=Adwaita` → `current` es `Adwaita` y
     `configured` es `true`.
   - `test_icon_theme_set_writes_the_default_file`: `--set Papirus-Dark` →
     código 0 y el fichero contiene `[Icon Theme]` y `Name=Papirus-Dark`.
   - `test_icon_theme_set_rejects_an_unknown_theme`: `--set NoExiste` → código 1,
     mensaje en stderr y el fichero no se crea.
   - `test_icon_theme_set_needs_a_theme`: `--set` sin valor → código 2.
2. **Implementación** en el CLI:
   - `DEFAULT_ICON_THEME: Final[str] = "Papirus-Dark"`.
   - `IconThemeState` (dataclass frozen+slots, con `to_json()`, al estilo de
     `PowerProfileState`).
   - `icon_theme_dirs() -> list[Path]`, `installed_icon_themes() -> list[str]`,
     `icon_theme_preview(theme: str) -> str`,
     `read_icon_theme_file(path: Path) -> str`,
     `write_icon_theme(name: str) -> None` (escritura atómica: temporal +
     `os.replace`, permisos 0644),
     `icon_theme_state() -> IconThemeState`, `icon_theme_apply(name: str) -> int`.
   - Dispatcher: `if cmd == "icon-theme":` con `--set`; y `icon-theme` en el
     mensaje de uso.
3. **Verificar**: `uv run pytest tests/test_caparazon_wm.py -q` en verde.

## Tarea 2 — JS: leer `~/.icons/default`

Ficheros: `modules/icons/IconTheme.js`, `tests/support/icon_theme_harness.js`,
`tests/test_icon_theme.py`.

1. **Test rojo**: dos escenarios nuevos en el harness —`default_theme_is_read`
   (devuelve el `Name=` de `[Icon Theme]`) y `missing_default_gives_empty`— y
   sus casos en `tests/test_icon_theme.py`.
2. **Implementación**: `defaultIconTheme(text)` en `IconTheme.js`, con el
   mismo estilo que `iconTheme(text)`: ignora comentarios y secciones ajenas,
   quita comillas y recorta.
3. **Verificar**: `uv run pytest tests/test_icon_theme.py -q` en verde.

## Tarea 3 — QML: saber si la sesión es niri

Ficheros: `modules/icons/CompositorService.qml` (nuevo),
`modules/icons/qmldir`, `tests/test_icon_theme_niri.py` (nuevo).

1. **Test rojo** en `tests/test_icon_theme_niri.py` (contrato por texto, como
   `tests/test_shell_qml_cli.py`):
   - `CompositorService.qml` invoca `caparazon-wm` con `detect`.
   - `qmldir` declara `singleton CompositorService 1.0 CompositorService.qml`.
   - `CompositorService.qml` expone `niri` a partir de `compositor`.
2. **Implementación**: singleton con `Process` + `StdioCollector`
   (`command: ["caparazon-wm", "detect"]`), `readonly property string compositor`
   y `readonly property bool niri`. Una sola consulta por proceso.
3. **Verificar**: `uv run pytest tests/test_icon_theme_niri.py -q` en verde.

## Tarea 4 — QML: el panel de iconos

Ficheros: `modules/secondmenu/IconThemePanel.qml` (nuevo),
`tests/test_icon_theme_niri.py`.

1. **Test rojo**:
   - El panel llama a `caparazon-wm icon-theme` y a
     `caparazon-wm icon-theme --set`.
   - El panel **no** escribe ficheros: no menciona `~/.icons/default` ni
     `FileView` sobre ese fichero (la puerta es el CLI).
2. **Implementación**:
   - Al cargar: `Process` con `["caparazon-wm", "icon-theme"]` → `JSON.parse` →
     `themes`, `current`, `defaultTheme`, `previews`.
   - `GridView` con los temas: miniatura (la ruta de `previews`, o el icono
     genérico de `IconResolver` si no hay), el nombre y la marca del activo.
   - Al elegir uno que no es el actual: `Process` con
     `["caparazon-wm", "icon-theme", "--set", nombre]` → si el código es 0,
     avisa de que la shell se reinicia; si no, `errorMessage` con la salida de
     error del comando.
   - `IconResolver` para el icono genérico y `Theme` para los colores.
3. **Verificar**: `uv run pytest tests/test_icon_theme_niri.py -q` en verde.

## Tarea 5 — QML: la categoría dinámica en el submenú

Ficheros: `modules/secondmenu/SecondMenu.qml`, `tests/test_icon_theme_niri.py`.

1. **Test rojo**:
   - `SecondMenu.qml` filtra las categorías con `CompositorService.niri`.
   - La categoría nueva tiene la clave `iconos`.
   - El `Loader` monta `IconThemePanel` para esa categoría.
2. **Implementación**:
   - `baseCategories`: las cuatro categorías de hoy, sin tocar.
   - `iconCategory`: `{ key: "iconos", icon: "preferences-desktop-theme", label: "Iconos" }`.
   - `categories`: `CompositorService.niri ? baseCategories.concat([iconCategory]) : baseCategories`.
   - `Loader.sourceComponent`: `if (root.category === "iconos") return iconComponent;`
     y su `Component` con `IconThemePanel`.
3. **Verificar**: `uv run pytest tests/test_icon_theme_niri.py -q` en verde.

## Tarea 6 — QML: reiniciar la shell cuando cambia el tema

Ficheros: `modules/icons/IconThemeWatcher.qml`, `modules/icons/IconTheme.js`,
`tests/test_icon_theme_niri.py`.

1. **Test rojo**:
   - `IconThemeWatcher.qml` vigila `.icons/default`.
   - Usa `IconTheme.defaultIconTheme` y su decisión de reinicio.
   - El reinicio es el mismo `requestRestart()` de siempre (no hay un segundo
     camino de reinicio).
2. **Implementación**:
   - `FileView` nuevo sobre `~/.icons/default` (`watchChanges: true`,
     `printErrors: false`) y `property string currentDefaultTheme` con su
     `defaultBaselineKnown`.
   - `checkDefaultTheme()` → `IconTheme.themeDecision(...)` (la misma decisión
     de línea base que KDE): el primer valor observado **no** reinicia (el
     proceso ya arrancó con él); un valor distinto posterior sí.
   - `scheduleCheck()` llama a `checkTheme()` y a `checkDefaultTheme()`; el
     `Timer` de seguridad de 5 s cubre también el caso de que el fichero
     aparezca después (lo escribe el instalador o el panel).
   - En KDE el comportamiento no cambia: `kdeglobals` se sigue vigilando igual.
3. **Verificar**: `uv run pytest tests/test_icon_theme_niri.py -q` en verde.

## Tarea 7 — Instalador: default y aviso

Ficheros: `install.sh`, `tests/test_install_compositor_agnostic.py`.

1. **Test rojo**:
   - `test_the_installer_sets_the_default_icon_theme_on_niri`: con
     `XDG_CURRENT_DESKTOP=niri` y un `HOME` temporal, tras instalar existe
     `~/.icons/default` con `Name=Papirus-Dark`.
   - `test_the_installer_keeps_the_users_icon_theme`: si `~/.icons/default` ya
     existe con otro tema, el instalador no lo toca.
   - `test_the_installer_warns_when_papirus_is_missing`: aviso con
     `papirus-icon-theme` (se salta si el paquete ya está instalado, como el
     test de `power-profiles-daemon`).
2. **Implementación**:
   - `install_niri_icon_theme()`: si `~/.icons/default` no existe, escribe el
     default llamando al CLI del repo
     (`python3 "$REPO/integration/bin/caparazon-wm.py" icon-theme --set Papirus-Dark`),
     para que la escritura tenga un solo sitio. Si existe, no se toca.
   - La función se llama en el flujo `instalar`, en la parte de niri.
   - En la rama no-KDE de `install_theme`, aviso de `papirus-icon-theme` con el
     comando apt exacto, junto al aviso que ya hay de
     `power-profiles-daemon`.
3. **Verificar**: `uv run pytest tests/test_install_compositor_agnostic.py -q`
   en verde.

## Tarea 8 — Documentación

Fichero: `README.md`.

1. `papirus-icon-theme` en la tabla de requisitos de niri y en su comando
   `apt install`.
2. Sección corta "Tema de iconos en niri": el default (Papirus-Dark), cómo
   cambiarlo desde la categoría "Iconos" del submenú y el aviso de que la
   shell se reinicia al aplicarlo.

## Tarea 9 — Verificación final

1. `uv run pytest -q` → toda la suite en verde.
2. `uv run ruff check` → sin errores nuevos (los 29 preexistentes fuera del
   alcance del `include` del proyecto no se tocan).
3. `bash -n install.sh` y `shellcheck install.sh` → limpio.
4. Prueba en vivo del CLI:
   `caparazon-wm icon-theme` (JSON), `--set Papirus-Dark`, comprobar el
   fichero, y restaurar el valor que hubiera.
5. Prueba en vivo del QML: una instancia de `quickshell` con el repositorio
   (con la salida a un fichero) → "Configuration Loaded" y cero errores QML.
6. Comprobación de que los iconos resuelven: con el tema puesto,
   `Quickshell.iconPath("preferences-desktop-theme")` devuelve una ruta real
   (no la genérica).
7. `git status` para ver exactamente qué se ha tocado. **Sin commit**: se
   espera a que el usuario lo pida.

## Riesgos

- El reinicio es real: al aplicar un tema, la shell se reinicia y el menú se
  cierra. Sin guardian en niri, el reinicio usa `relaunchCommand`, que
  relanza el proceso con su mismo argv; con systemd, `restartCommand`.
- La línea base del watcher evita el bucle de reinicios: el valor observado
  por primera vez no reinicia.
- `~/.icons/default` también afecta a las demás apps de la sesión que lean el
  tema al arrancar: es el comportamiento estándar de un tema del sistema.

## Ampliación 2026-11-22 — include del config, unificación y `?fallback=`

Pendientes de esta sesión (todos cerrados; **sin commit**):

1. **CLI sigue los `include` de niri** (TDD): `read_icon_theme_file` y
   `write_icon_theme` expanden `include "…"` en orden de carga; gana el
   último valor; `--set` escribe en el archivo dueño (p. ej.
   `config.d/40-environment.kdl`) y no appenda un bloque duplicado en
   `config.kdl`. Tests nuevos en `tests/test_caparazon_wm.py`.
2. **Fuente única del tema**: `config.d/40-environment.kdl` con
   `CAPARAZON_ICON_THEME "Tela-dark"` y `QS_ICON_THEME "Tela-dark"`; fuera el
   bloque `environment` duplicado de `config.kdl`. `niri validate` OK;
   `caparazon-wm icon-theme` → `current=Tela-dark, configured=true`.
3. **`?fallback=` y bypass del resolver**: `IconNames.js` recorta la query
   (`stripQuery`); `MusicButton` y `DockApp` usan `IconResolver.source` en
   vez de `Quickshell.iconPath(name, fallback)` (que generaba
   `image://icon/…?fallback=…` y los avisos `media-*-symbolic?fallback=` /
   `application-x-executable`).
4. **Env de quickshell**: `~/.config/autostart/caparazon.desktop` lleva
   `QS_ICON_THEME=Tela-dark CAPARAZON_ICON_THEME=Tela-dark` en el `Exec`
   (quickshell no hereda el `environment` de niri: arranca vía autostart,
   padre `systemd --user`).
5. **Verificación**: `pytest` → 690 passed, 1 skipped; `ruff` → 29
   preexistentes (0 nuevos); `qmllint` → 0 errores (avisos `target:
   appIcon` preexistentes en `DockApp.qml`).

Pendiente del usuario: `sudo apt install xwayland-satellite` para apps X11;
reiniciar la shell (o la sesión) para que el `Exec` del autostart y los
cambios QML tomen efecto.

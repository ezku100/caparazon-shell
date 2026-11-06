# Estilos de color de la shell (Material / OLED / Perla) — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Ejecución en este proyecto: nativa (`superpowers:executing-plans`).** El
> AGENTS.md del usuario fija modo económico: no se delega a categorías de pago.

**Goal:** Añadir a Caparazón tres estilos de color (Material, OLED y Perla)
que siguen al acento de KDE, con una categoría nueva en el menú secundario
para elegirlos en vivo.

**Architecture:** El motor `accent-theme` gana una clave opcional `saturation`
por descriptor y aplica un boost HSV a la plantilla antes de publicarla. La
shell publica tres plantillas con los mismos 17 tokens y tres descriptores;
el motor genera tres paletas en la misma pasada de matugen. En la shell,
`ThemeStyle.qml` guarda el estilo elegido y `MatugenPalette.qml` lee la paleta
que toca, así que `Theme.qml` (y toda la interfaz) se repinta sin cambios.

**Tech Stack:** Python 3.11 (motor: `colorsys`, pytest, ruff ALL,
basedpyright all), QML/Quickshell 0.3.x, bash (`install.sh`), matugen 4.x.

**Spec:** `docs/superpowers/specs/2026-11-06-estilos-material-oled-perla-design.md`

## Global Constraints

- Tokens de la shell: exactamente los 17 de
  `integration/theme/required-tokens.txt`. El archivo **no cambia**: es el
  mismo contrato para las tres plantillas.
- Motor: sin dependencias nuevas (solo `colorsys` de la stdlib, ya usado en
  `accent.py`). `ruff` con `select = ALL` y `basedpyright` en modo `all`.
- Motor: los errores de descriptor usan `RegistryError` con mensaje en
  español, como los existentes.
- Shell: todo color de interfaz sale de `Theme.*`; no se añaden hex nuevos
  fuera de las plantillas. Los hex fijos existentes (§4.3 de la spec) **no se
  tocan**.
- `theme/Theme.qml` **no se modifica**.
- Comentarios y textos de interfaz en español.
- Calidad antes de cada commit de entrega: `uv run pytest -q`,
  `uv run ruff check .`, `uv run basedpyright` (en los dos repos).
- Mensajes de commit en el estilo del repo: `Motor: …`, `Tema: …`,
  `Instalador: …`, `Menus: …`, `Docs: …`.
- Rutas: motor en `~/.local/share/accent-theme/source`; shell en
  `~/Projects/caparazon-shell`.

## Review Focus

Los cinco fallos que la spec implica y que más probablemente muerdan a quien
use esto. Cada uno tiene su test en la tarea que posee el código:

1. **Estilo guardado con un valor desconocido o `style.json` corrupto** → la
   shell tiene que caer a Material sin romperse (Tarea 5).
2. **Falta la paleta del estilo elegido** (instalación a medias, caché
   borrada) → la shell no puede quedarse sin colores: valores de reserva y el
   panel avisa (Tareas 5 y 6).
3. **Cambia el acento de KDE con OLED activo** → las tres paletas se regeneran
   y la shell mantiene el estilo (Tareas 2 y 7).
4. **Gris con tinte en la plantilla OLED** → el boost lo tiñe; los grises de
   la plantilla son neutros a propósito (Tareas 1 y 3).
5. **`register` reescribe el descriptor instalado** → si no propaga
   `saturation`, el boost se pierde en silencio al reinstalar (Tarea 2).

---

## Estructura de archivos

### Motor (`~/.local/share/accent-theme/source`)

| Archivo | Responsabilidad |
|---|---|
| `src/accent_theme/transform.py` (nuevo) | Boost de saturación HSV sobre un documento `{token: hex}` |
| `src/accent_theme/registry.py` (modificar) | Leer y validar `saturation`; `Descriptor`; `TemplateRegistration.saturation` |
| `src/accent_theme/cli.py` (modificar) | `register` propaga `saturation`; `generate` transforma el staging; `doctor` informa |
| `tests/test_transform.py` (nuevo) | Contrato del boost |
| `tests/test_registry.py` (modificar) | Contrato del descriptor con `saturation` |
| `tests/test_cli.py` (modificar) | `generate` publica transformado; `register` conserva la clave |
| `README.md`, `GUIA.md` (modificar) | Documentar la clave opcional |

### Shell (`~/Projects/caparazon-shell`)

| Archivo | Responsabilidad |
|---|---|
| `integration/theme/quickshell-oled.json` (nuevo) | Plantilla OLED (17 tokens) |
| `integration/theme/quickshell-perla.json` (nuevo) | Plantilla Perla (17 tokens) |
| `integration/theme/accent-theme-oled.toml` (nuevo) | Descriptor OLED con `saturation = 1.45` |
| `integration/theme/accent-theme-perla.toml` (nuevo) | Descriptor Perla |
| `install.sh` (modificar) | Registra y valida las tres paletas; desinstala las tres |
| `theme/ThemeStyle.qml` (nuevo) | Estilo activo + persistencia + nombre de paleta |
| `theme/qmldir` (modificar) | Registra el singleton `ThemeStyle` |
| `theme/MatugenPalette.qml` (modificar) | Lee la paleta del estilo activo |
| `modules/appmenu/RailButton.qml` (modificar) | Propiedad `glyph` para el kanji |
| `modules/secondmenu/SecondMenu.qml` (modificar) | Categoría `configs` + rama del `Loader` |
| `modules/secondmenu/ShellConfigPanel.qml` (nuevo) | Panel de estilos |
| `tests/test_theme_install_contract.py` (modificar) | Tres plantillas y tres descriptores |
| `tests/test_shell_style.py` (nuevo) | Contrato de `ThemeStyle` y `MatugenPalette` |
| `tests/test_second_menu_wiring.py` (modificar) | Categoría `configs` y `glyph` |
| `tests/test_category_rail_contrast.py` (modificar) | El glifo sigue el tinte del icono |
| `README.md` (modificar) | Sección «Estilos de color» |

---

## Task 1: Transform de saturación en el motor

**Files:**
- Create: `src/accent_theme/transform.py`
- Create: `tests/test_transform.py`

**Interfaces:**
- Consumes: `accent_theme.accent.Accent`, `rgb_to_hsv`, `hsv_to_hex` (ya
  existen).
- Produces: `boost_saturation(document: Mapping[str, str], factor: float) -> dict[str, str]`.

- [ ] **Step 1: Escribir el test que falla**

```python
# tests/test_transform.py
from accent_theme.transform import boost_saturation


def test_boost_saturation_keeps_neutral_colors() -> None:
    assert boost_saturation({"surface": "#080808"}, 1.45) == {"surface": "#080808"}


def test_boost_saturation_clamps_at_full_chroma() -> None:
    assert boost_saturation({"primary": "#ff0000"}, 1.45) == {"primary": "#ff0000"}


def test_boost_saturation_leaves_non_hex_values() -> None:
    assert boost_saturation({"surface": "transparent"}, 1.45) == {
        "surface": "transparent"
    }


def test_boost_saturation_increases_chroma() -> None:
    from accent_theme.accent import Accent, rgb_to_hsv

    original = Accent(0x84, 0xCF, 0xFF)
    boosted = boost_saturation({"primary": "#84cfff"}, 1.45)["primary"]
    result = Accent(int(boosted[1:3], 16), int(boosted[3:5], 16), int(boosted[5:7], 16))
    assert rgb_to_hsv(result).saturation > rgb_to_hsv(original).saturation
    assert rgb_to_hsv(result).saturation <= 1.0
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_transform.py -q`
Expected: FAIL con `ModuleNotFoundError: No module named 'accent_theme.transform'`

- [ ] **Step 3: Implementar `boost_saturation`**

```python
# src/accent_theme/transform.py
"""Transformaciones de color sobre las paletas que publica el motor."""

from __future__ import annotations

import re
from typing import TYPE_CHECKING, Final

from accent_theme.accent import Accent, hsv_to_hex, rgb_to_hsv

if TYPE_CHECKING:
    from collections.abc import Mapping

HEX_COLOR_PATTERN: Final = re.compile(r"^#[0-9a-fA-F]{6}$")


def boost_saturation(document: Mapping[str, str], factor: float) -> dict[str, str]:
    """Multiplica la saturación HSV de cada color hexadecimal del documento."""
    return {key: _boost_color(value, factor) for key, value in document.items()}


def _boost_color(value: str, factor: float) -> str:
    if HEX_COLOR_PATTERN.fullmatch(value) is None:
        return value
    accent = Accent(
        int(value[1:3], 16),
        int(value[3:5], 16),
        int(value[5:7], 16),
    )
    hsv = rgb_to_hsv(accent)
    return hsv_to_hex(hsv.hue, hsv.saturation * factor, hsv.value)
```

Nota: `hsv_to_hex` ya acota la saturación a `[0, 1]`; no hay que repetirlo.

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_transform.py -q`
Expected: 4 passed

- [ ] **Step 5: Calidad y commit**

Run: `uv run ruff check . && uv run basedpyright`
Expected: sin errores

```bash
git add src/accent_theme/transform.py tests/test_transform.py
git commit -m "Motor: transform de saturación para las plantillas"
```

---

## Task 2: `saturation` en el descriptor y en el pipeline

**Files:**
- Modify: `src/accent_theme/registry.py`
- Modify: `src/accent_theme/cli.py`
- Modify: `tests/test_registry.py`
- Modify: `tests/test_cli.py`
- Modify: `README.md`
- Modify: `GUIA.md`

**Interfaces:**
- Consumes: `transform.boost_saturation(document, factor)` (Tarea 1).
- Produces: `registry.Descriptor(name: str, input_path: str, output_path: str,
  saturation: float | None)`; `registry.parse_descriptor(path) -> Descriptor`;
  `registry.TemplateRegistration.saturation: float | None`.

- [ ] **Step 1: Escribir los tests que fallan (registro)**

En `tests/test_registry.py`, adaptar las llamadas existentes a
`parse_descriptor(...)` al nuevo `Descriptor` (`.name`, `.input_path`,
`.output_path`) y añadir:

```python
def test_descriptor_saturation_is_optional(tmp_path: Path) -> None:
    descriptor = write_descriptor(tmp_path, 'name = "demo"\ninput_path = "in.json"\noutput_path = "out.json"\n')
    assert parse_descriptor(descriptor).saturation is None


def test_descriptor_saturation_is_read(tmp_path: Path) -> None:
    descriptor = write_descriptor(tmp_path, 'name = "demo"\ninput_path = "in.json"\noutput_path = "out.json"\nsaturation = 1.45\n')
    assert parse_descriptor(descriptor).saturation == 1.45


def test_descriptor_saturation_below_one_is_rejected(tmp_path: Path) -> None:
    descriptor = write_descriptor(tmp_path, 'name = "demo"\ninput_path = "in.json"\noutput_path = "out.json"\nsaturation = 0.8\n')
    with pytest.raises(RegistryError):
        parse_descriptor(descriptor)


def test_descriptor_saturation_must_be_a_number(tmp_path: Path) -> None:
    descriptor = write_descriptor(tmp_path, 'name = "demo"\ninput_path = "in.json"\noutput_path = "out.json"\nsaturation = "alta"\n')
    with pytest.raises(RegistryError):
        parse_descriptor(descriptor)
```

Si `tests/test_registry.py` no tiene un helper `write_descriptor`, añadirlo
junto a los tests existentes (crea `in.json` para que `load_registrations`
encuentre el `input_path`; mira cómo lo hacen hoy los tests del archivo).

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_registry.py -q`
Expected: FAIL (no existe `Descriptor.saturation`)

- [ ] **Step 3: Implementar en `registry.py`**

- Añadir `saturation` a `REQUIRED_KEYS` **no**: crear
  `OPTIONAL_KEYS: Final = frozenset({"saturation"})` y ampliar la validación
  de claves desconocidas a `REQUIRED_KEYS | OPTIONAL_KEYS`.
- Añadir el dataclass `Descriptor` (campos de la sección Interfaces).
- `parse_descriptor` devuelve `Descriptor`: acepta `str` en las tres claves
  obligatorias y `float`/`int` en `saturation`; un valor no numérico en
  `saturation` es error; `saturation < 1.0` es error (nuevo
  `RegistryError.invalid_saturation`).
- `load_registrations` usa el `Descriptor` y pasa `saturation` a
  `TemplateRegistration`.
- `_handle_register` en `cli.py` usa los atributos del `Descriptor` y, al
  reescribir el descriptor instalado, añade `saturation` cuando no es `None`.

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_registry.py -q`
Expected: PASS

- [ ] **Step 5: Escribir los tests que fallan (pipeline)**

En `tests/test_cli.py`, siguiendo los helpers que ya usa el archivo (matugen
falso y `tmp_path`):

```python
def test_generate_publishes_the_boosted_palette(...) -> None:
    # descriptor con saturation = 1.45, matugen falso que escribe "#84cfff"
    ...
    assert "#6bc4ff" in output.read_text(encoding="utf-8")  # valor más saturado


def test_register_keeps_the_saturation_key(...) -> None:
    ...
    assert "saturation = 1.45" in installed_descriptor.read_text(encoding="utf-8")
```

El valor exacto del boost se calcula con el mismo `boost_saturation` (importarlo
en el test) en vez de escribirlo a mano.

- [ ] **Step 6: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_cli.py -q`
Expected: FAIL en los dos tests nuevos

- [ ] **Step 7: Implementar en `cli.py`**

- `_handle_generate`: antes de `staging_path.replace(output_path)`, si
  `registration.saturation is not None`, leer el staging como JSON, aplicar
  `boost_saturation`, y reescribirlo en el mismo staging con escritura
  atómica (`_atomic_write_text` ya existe en el archivo).
- `_handle_register`: incluir `saturation` en el descriptor instalado.
- `_handle_doctor`: en la línea de cobertura, añadir `(saturación X)` a las
  integraciones que la tengan.

- [ ] **Step 8: Ejecutar y ver que pasa**

Run: `uv run pytest -q`
Expected: toda la suite del motor en verde

- [ ] **Step 9: Documentar la clave**

En `README.md` y `GUIA.md` del motor: tabla de claves del descriptor con
`saturation` como opcional (multiplicador HSV `>= 1.0`), el ejemplo de la
plantilla OLED y el aviso de que un motor viejo la rechaza.

- [ ] **Step 10: Calidad y commit**

Run: `uv run ruff check . && uv run basedpyright && uv run pytest -q`

```bash
git add src/accent_theme/registry.py src/accent_theme/cli.py tests/test_registry.py tests/test_cli.py README.md GUIA.md
git commit -m "Motor: saturation por descriptor y boost en generate"
```

---

## Task 3: Las tres plantillas de la shell

**Files:**
- Create: `integration/theme/quickshell-oled.json`
- Create: `integration/theme/quickshell-perla.json`
- Create: `integration/theme/accent-theme-oled.toml`
- Create: `integration/theme/accent-theme-perla.toml`
- Modify: `tests/test_theme_install_contract.py`

**Interfaces:**
- Consumes: el formato de `integration/theme/quickshell-matugen.json`
  (17 claves, valores `{{colors.<rol>.dark.hex}}`).
- Produces: los tres archivos de plantilla y los tres descriptores que la
  Tarea 4 registra.

- [ ] **Step 1: Escribir el test que falla**

En `tests/test_theme_install_contract.py`:

```python
THEME_DIR = REPOSITORY_ROOT / "integration" / "theme"
TEMPLATES = ["quickshell-matugen.json", "quickshell-oled.json", "quickshell-perla.json"]
DESCRIPTORS = ["accent-theme.toml", "accent-theme-oled.toml", "accent-theme-perla.toml"]


def test_the_three_templates_share_the_same_tokens() -> None:
    required = set((THEME_DIR / "required-tokens.txt").read_text(encoding="utf-8").split())
    for name in TEMPLATES:
        document = json.loads((THEME_DIR / name).read_text(encoding="utf-8"))
        assert set(document) == required, name


def test_only_the_oled_descriptor_boosts_saturation() -> None:
    oled = (THEME_DIR / "accent-theme-oled.toml").read_text(encoding="utf-8")
    material = (THEME_DIR / "accent-theme.toml").read_text(encoding="utf-8")
    perla = (THEME_DIR / "accent-theme-perla.toml").read_text(encoding="utf-8")
    assert "saturation = 1.45" in oled
    assert "saturation" not in material
    assert "saturation" not in perla
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_theme_install_contract.py -q`
Expected: FAIL por archivos inexistentes

- [ ] **Step 3: Crear las plantillas**

`integration/theme/quickshell-oled.json` — grises **neutros** (saturación 0)
en las superficies; acentos del esquema oscuro:

```json
{
  "surface": "#000000",
  "surfaceContainerLowest": "#000000",
  "surfaceContainerLow": "#080808",
  "surfaceContainer": "#0F0F0F",
  "surfaceContainerHigh": "#161616",
  "surfaceContainerHighest": "#1E1E1E",
  "fgSurface": "#F2F2F2",
  "fgSurfaceVariant": "#B8B8B8",
  "outline": "#6E6E6E",
  "outlineVariant": "#2A2A2A",
  "primary": "{{colors.primary.dark.hex}}",
  "fgPrimary": "{{colors.on_primary.dark.hex}}",
  "secondary": "{{colors.secondary.dark.hex}}",
  "tertiary": "{{colors.tertiary.dark.hex}}",
  "error": "{{colors.error.dark.hex}}",
  "errorContainer": "{{colors.error_container.dark.hex}}",
  "fgErrorContainer": "{{colors.on_error_container.dark.hex}}"
}
```

`integration/theme/quickshell-perla.json` — superficies perla fijas; acentos
del esquema **claro**:

```json
{
  "surface": "#FAF9F6",
  "surfaceContainerLowest": "#FFFFFF",
  "surfaceContainerLow": "#F4F2ED",
  "surfaceContainer": "#EDEAE4",
  "surfaceContainerHigh": "#E5E1DA",
  "surfaceContainerHighest": "#DBD6CD",
  "fgSurface": "#1C1B19",
  "fgSurfaceVariant": "#56534D",
  "outline": "#9B968C",
  "outlineVariant": "#D6D1C7",
  "primary": "{{colors.primary.light.hex}}",
  "fgPrimary": "{{colors.on_primary.light.hex}}",
  "secondary": "{{colors.secondary.light.hex}}",
  "tertiary": "{{colors.tertiary.light.hex}}",
  "error": "{{colors.error.light.hex}}",
  "errorContainer": "{{colors.error_container.light.hex}}",
  "fgErrorContainer": "{{colors.on_error_container.light.hex}}"
}
```

- [ ] **Step 4: Crear los descriptores**

`integration/theme/accent-theme-oled.toml`:

```toml
name = "caparazon-shell-oled"
input_path = "~/.config/accent-theme/templates/caparazon-shell-oled/quickshell-oled.json"
output_path = "~/.cache/caparazon/colors-oled.json"
saturation = 1.45
```

`integration/theme/accent-theme-perla.toml`:

```toml
name = "caparazon-shell-perla"
input_path = "~/.config/accent-theme/templates/caparazon-shell-perla/quickshell-perla.json"
output_path = "~/.cache/caparazon/colors-perla.json"
```

- [ ] **Step 5: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_theme_install_contract.py -q`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add integration/theme/quickshell-oled.json integration/theme/quickshell-perla.json integration/theme/accent-theme-oled.toml integration/theme/accent-theme-perla.toml tests/test_theme_install_contract.py
git commit -m "Tema: plantillas OLED y Perla con los mismos tokens"
```

---

## Task 4: `install.sh` registra y valida las tres paletas

**Files:**
- Modify: `install.sh`
- Modify: `tests/test_theme_install_contract.py`

**Interfaces:**
- Consumes: los tres descriptores de la Tarea 3.
- Produces: `~/.cache/caparazon/colors.json`, `colors-oled.json` y
  `colors-perla.json` tras instalar.

- [ ] **Step 1: Escribir el test que falla**

```python
def test_install_registers_and_validates_the_three_palettes() -> None:
    script = (REPOSITORY_ROOT / "install.sh").read_text(encoding="utf-8")
    for name in ("accent-theme-oled.toml", "accent-theme-perla.toml"):
        assert name in script
    for palette in ("colors-oled.json", "colors-perla.json"):
        assert palette in script
    assert script.count("register --app caparazon-shell") == 3
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_theme_install_contract.py -q`
Expected: FAIL

- [ ] **Step 3: Implementar en `install.sh`**

- Variables nuevas junto a las existentes: descriptores OLED y Perla, sus
  directorios de plantilla instalada (`templates/caparazon-shell-oled`,
  `templates/caparazon-shell-perla`), sus descriptores instalados
  (`templates.d/caparazon-shell-oled.toml`, `…-perla.toml`) y sus paletas
  (`$HOME/.cache/caparazon/colors-oled.json`, `colors-perla.json`).
- `register_caparazon_theme`: tres `register` (apps `caparazon-shell`,
  `caparazon-shell-oled`, `caparazon-shell-perla`) y un solo `generate` al
  final.
- `validate_palette`: recorrer las tres paletas; el error nombra la paleta y
  los tokens que faltan en ella.
- `remove_caparazon_theme`: borrar también los dos descriptores instalados,
  los dos directorios de plantilla y las dos paletas nuevas.

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_theme_install_contract.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_theme_install_contract.py
git commit -m "Instalador: registra y valida las tres paletas"
```

---

## Task 5: Capa de tema en la shell (estilo activo)

**Files:**
- Create: `theme/ThemeStyle.qml`
- Modify: `theme/qmldir`
- Modify: `theme/MatugenPalette.qml`
- Create: `tests/test_shell_style.py`

**Interfaces:**
- Produces: `ThemeStyle.style` (`"material"` | `"oled"` | `"perla"`),
  `ThemeStyle.paletteFile` (`"colors.json"` | `"colors-oled.json"` |
  `"colors-perla.json"`), `ThemeStyle.setStyle(value)`,
  `ThemeStyle.configPath`, `ThemeStyle.palettePathFor(name)`.
- Consumes: `MatugenPalette` sigue exponiendo los 17 tokens.

- [ ] **Step 1: Escribir el test que falla**

```python
# tests/test_shell_style.py
THEME_STYLE = REPOSITORY_ROOT / "theme" / "ThemeStyle.qml"
PALETTE = REPOSITORY_ROOT / "theme" / "MatugenPalette.qml"
QMLDIR = REPOSITORY_ROOT / "theme" / "qmldir"


def test_theme_style_knows_the_three_styles() -> None:
    contents = THEME_STYLE.read_text(encoding="utf-8")
    for name in ("material", "oled", "perla", "colors-oled.json", "colors-perla.json"):
        assert name in contents


def test_theme_style_persists_in_the_config_dir() -> None:
    contents = THEME_STYLE.read_text(encoding="utf-8")
    assert "/.config" in contents
    assert "style.json" in contents


def test_palette_follows_the_active_style() -> None:
    assert "ThemeStyle.paletteFile" in PALETTE.read_text(encoding="utf-8")


def test_qmldir_registers_the_style_singleton() -> None:
    assert "singleton ThemeStyle" in QMLDIR.read_text(encoding="utf-8")
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_shell_style.py -q`
Expected: FAIL (no existen los archivos)

- [ ] **Step 3: Crear `theme/ThemeStyle.qml`**

Singleton con el patrón de `PanelSettings.qml`: `FileView` + `JsonAdapter`
sobre `~/.config/caparazon/style.json`, `Process` que crea el archivo si
falta, escritura atómica con `bash … > "$2.tmp" && mv`, bandera `loaded`.

```qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    readonly property var styles: ["material", "oled", "perla"]
    readonly property string configDir: Quickshell.env("HOME") + "/.config/caparazon"
    readonly property string configPath: configDir + "/style.json"

    property string style: "material"
    property bool loaded: false

    readonly property string paletteFile: {
        if (root.style === "oled")
            return "colors-oled.json";
        if (root.style === "perla")
            return "colors-perla.json";
        return "colors.json";
    }

    function palettePathFor(name) {
        const file = name === "oled" ? "colors-oled.json"
            : name === "perla" ? "colors-perla.json"
            : "colors.json";
        return root.paletteCacheDir + "/" + file;
    }

    function setStyle(value) {
        if (root.styles.indexOf(value) === -1)
            return;
        if (root.style === value)
            return;
        root.style = value;
    }

    function save() {
        if (!root.loaded)
            return;
        writer.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"",
            "bash",
            "{\"style\":\"" + root.style + "\"}",
            root.configPath
        ];
        writer.running = true;
    }

    onStyleChanged: save()

    // + Process ensureFile (crea el JSON si falta), Process writer,
    //   FileView con watchChanges, JsonAdapter { property string style: "material" }
    //   y Connections onLoaded: valida el valor leído contra root.styles,
    //   cae a "material" si no está en la lista y marca loaded = true.
}
```

`paletteCacheDir` es el mismo cálculo XDG que `MatugenPalette.cacheDir` +
`/caparazon`.

- [ ] **Step 4: Registrar el singleton y leer la paleta del estilo**

- `theme/qmldir`: añadir `singleton ThemeStyle 1.0 ThemeStyle.qml`.
- `theme/MatugenPalette.qml`: `path: root.cacheDir + "/caparazon/" +
  ThemeStyle.paletteFile` y `onPathChanged: colorsFile.reload()`. El resto
  (los 17 tokens y los valores de reserva) no cambia.

- [ ] **Step 5: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_shell_style.py -q`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add theme/ThemeStyle.qml theme/qmldir theme/MatugenPalette.qml tests/test_shell_style.py
git commit -m "Tema: estilo de color activo y paleta por estilo"
```

---

## Task 6: Categoría «Configs de la shell» y panel de estilos

**Files:**
- Modify: `modules/appmenu/RailButton.qml`
- Modify: `modules/secondmenu/SecondMenu.qml`
- Create: `modules/secondmenu/ShellConfigPanel.qml`
- Modify: `tests/test_second_menu_wiring.py`
- Modify: `tests/test_category_rail_contrast.py`
- Modify: `README.md`

**Interfaces:**
- Consumes: `ThemeStyle.style`, `ThemeStyle.setStyle`, `ThemeStyle.palettePathFor`
  (Tarea 5) y `Theme.*`.
- Produces: categoría `configs` en el raíl y el panel `ShellConfigPanel`.

- [ ] **Step 1: Escribir los tests que fallan**

En `tests/test_second_menu_wiring.py`:

```python
def test_the_configs_category_uses_the_menu_kanji() -> None:
    contents = SECOND_MENU.read_text(encoding="utf-8")
    assert 'key: "configs"' in contents
    assert 'glyph: "猫"' in contents
    assert 'root.category === "configs"' in contents
    assert "ShellConfigPanel {" in contents
```

En `tests/test_category_rail_contrast.py`:

```python
def test_the_rail_glyph_uses_the_icon_tint() -> None:
    contents = RAIL_BUTTON.read_text(encoding="utf-8")
    glyph = re.search(r"text:\s*root\.glyph(.*?)\n\s*\}", contents, re.DOTALL)
    assert glyph is not None
    assert "Theme.textDim" in glyph.group(1)
    assert "selected" not in glyph.group(1)
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `uv run pytest tests/test_second_menu_wiring.py tests/test_category_rail_contrast.py -q`
Expected: FAIL

- [ ] **Step 3: Añadir `glyph` a `RailButton.qml`**

`property string glyph: ""`; un `Text` centrado, `visible: root.glyph !== ""`,
`text: root.glyph`, `color: hover.hovered ? Theme.text : Theme.textDim`,
`font.family: Theme.fontJP`, `font.pixelSize: 17`, `font.weight:
Font.DemiBold`. El `IconImage` existente gana `visible: root.glyph === ""`.
El bloque `colorizationColor` no se toca (lo fija el test actual).

- [ ] **Step 4: Añadir la categoría y la rama del `Loader`**

En `SecondMenu.qml`:

```qml
readonly property var categories: [
    { key: "calendario", icon: "notifications", label: "Calendario" },
    { key: "musica", icon: "audio", label: "Música" },
    { key: "sistema", icon: "utilities-system-monitor", label: "Monitor del sistema" },
    { key: "configs", glyph: "猫", label: "Configs de la shell" }
]
```

En el delegate: `icon: modelData.icon || ""` y `glyph: modelData.glyph || ""`.
En el `Loader`: `if (root.category === "configs") return configComponent;`.
Y el componente nuevo:

```qml
Component {
    id: configComponent
    ShellConfigPanel {
        anchors.fill: parent
    }
}
```

- [ ] **Step 5: Crear `ShellConfigPanel.qml`**

Estructura: título «Configs de la shell», subtítulo «Estilo de color» y tres
filas (una por estilo) con punto de selección, nombre, descripción y tres
muestras (fondo, superficie, acento).

- Las muestras salen de las tres paletas: el panel declara **tres**
  `FileView` + `JsonAdapter` (material, OLED, Perla) con los 17 tokens y los
  mismos valores de reserva que `MatugenPalette.qml`; cada fila referencia
  estáticamente su adapter (para que la bindings se actualicen al cambiar el
  acento).
- `readonly property var styleRows: [...]` con `{ key, label, note, bg,
  surface, accent }`; `Repeater` + `MouseArea` por fila.
- Clic en fila → `ThemeStyle.setStyle(modelData.key)`.
- Un `Process` (`bash -c 'for f in "$@"; do [ -f "$f" ] && basename "$f"; done'`)
  llena `property var availablePalettes: []`; una fila cuyo archivo no está
  aparece atenuada, sin `MouseArea`, con la nota «falta instalar esta paleta»;
  si el estilo **activo** no está disponible, se llama a
  `ThemeStyle.setStyle("material")`.
- Sin hex nuevos: los valores de reserva de los adapters son los de las
  plantillas y los de `MatugenPalette`.

- [ ] **Step 6: Ejecutar y ver que pasa**

Run: `uv run pytest tests/test_second_menu_wiring.py tests/test_category_rail_contrast.py -q`
Expected: PASS

- [ ] **Step 7: Documentar en el README**

Sección **Estilos de color**: los tres estilos, `~/.config/caparazon/style.json`,
que las tres paletas se regeneran al cambiar el acento de KDE y que la
categoría vive en el menú secundario.

- [ ] **Step 8: Calidad y commit**

Run: `uv run pytest -q && uv run ruff check . && uv run basedpyright`

```bash
git add modules/appmenu/RailButton.qml modules/secondmenu/SecondMenu.qml modules/secondmenu/ShellConfigPanel.qml tests/test_second_menu_wiring.py tests/test_category_rail_contrast.py README.md
git commit -m "Menus: categoría Configs de la shell con los tres estilos"
```

---

## Task 7: Verificación en vivo y publicación

**Files:** ninguno nuevo; se verifica lo construido.

- [ ] **Step 1: Instalar las dos piezas**

```bash
cd ~/Projects/caparazon-shell && ./install.sh
```
Expected: termina sin error y las tres paletas existen:

```bash
ls -l ~/.cache/caparazon/colors.json ~/.cache/caparazon/colors-oled.json ~/.cache/caparazon/colors-perla.json
```

- [ ] **Step 2: Estado del motor**

```bash
~/.local/bin/accent-theme doctor
```
Expected: `doctor: N integraciones correctas`, con `caparazon-shell`,
`caparazon-shell-oled` y `caparazon-shell-perla` entre ellas.

- [ ] **Step 3: Comprobar la saturación real**

```bash
~/.local/bin/accent-theme generate
python3 - <<'PY'
import json, colorsys, pathlib
for name in ("colors.json", "colors-oled.json", "colors-perla.json"):
    p = pathlib.Path.home() / ".cache/caparazon" / name
    data = json.loads(p.read_text())
    hexv = data["primary"].lstrip("#")
    r, g, b = (int(hexv[i:i+2], 16) / 255 for i in (0, 2, 4))
    print(name, data["primary"], "S=%.2f" % colorsys.rgb_to_hsv(r, g, b)[1])
PY
```
Expected: la `S` de `colors-oled.json` es mayor que la de `colors.json`
(multiplicada por 1.45 y acotada a 1.0); Perla tiene otro tono (rol claro).

- [ ] **Step 4: Prueba en vivo de la interfaz**

Con la shell corriendo (`quickshell -p ~/Projects/caparazon-shell` y
`journalctl --user -f _COMM=quickshell` en otra terminal):
1. Abrir el menú secundario → **Configs de la shell** (kanji 猫).
2. Elegir OLED → la barra, el dock y los menús se repintan en negro.
3. Elegir Perla → se repintan en blanco perla, con texto oscuro legible.
4. Cambiar el acento en *Preferencias del sistema → Colores* → las tres
   paletas se regeneran y la shell mantiene el estilo elegido.
5. Volver a Material y comprobar que todo luce como antes.
6. En el log: sin errores de `JsonAdapter` ni de `FileView`.

- [ ] **Step 5: Commits finales y subida a GitHub**

Motor (rama propia, para no tocar `main` sin permiso):

```bash
cd ~/.local/share/accent-theme/source
git switch -c feature/caparazon-styles
git push -u origin feature/caparazon-styles
```

Shell (rama actual del trabajo):

```bash
cd ~/Projects/caparazon-shell
git push
```

Expected: los dos `push` terminan con la rama publicada; se informa al usuario
de las dos ramas y del resultado de la verificación en vivo.

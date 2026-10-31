# Música: modo compacto con espectro — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir un modo compacto a la categoría Música del menú secundario: botón ⛶ que oculta letra, barra y botones, deja el álbum con el vinilo girando, pone un espectro de audio al pie y recuerda la elección.

**Architecture:** La lógica pura (mapeo y suavizado de barras) vive en un módulo JS probado con node. Un script python adapta el sampler de cava del plugin de Noctalia (`wavefeed.py`) y publica 32 valores en `~/.cache/caparazon/waves.json`; un componente QML autónomo (`Spectrum.qml`) lo lee y dibuja. La preferencia se guarda en `~/.cache/caparazon/music-panel.json` mediante un servicio pequeño (`MusicSettings.qml`). `MusicPanel.qml` solo cablea las piezas; no contiene lógica nueva de espectro.

**Tech Stack:** QML (Quickshell), JavaScript (módulos `.pragma library`), Python 3 (script de sampler), pytest + node (tests).

**Spec:** `docs/superpowers/specs/2026-10-30-musica-modo-compacto-design.md`

## Global Constraints

- Idioma de todo el código, comentarios y tests: **español**.
- Todo el trabajo vive en `modules/secondmenu/MusicPanel.qml` y `modules/music/`; **no** se toca la barra, el dock ni el tema.
- Los módulos JS puros empiezan con `.pragma library` y se prueban con un harness de node en `tests/support/` que imprime `id\tPASS|FAIL\tdetalle` por stdout (patrón de `art_urls_harness.js`).
- Los tests de cableado QML son comprobaciones estáticas de texto sobre el `.qml` (patrón de `test_music_art.py`, con helper `contents(path)`).
- `uv run pytest -q` debe quedar en verde; `uv run ruff check tests` limpio (`select = ["ALL"]`).
- Escrituras de JSON: atómicas (`printf` a `.tmp` + `mv`), como `ClipboardHistoryService.qml`.
- Ficheros de estado en `~/.cache/caparazon/` (`waves.json`, `music-panel.json`, `cava.conf`, `cava.fifo`).
- Sin capturas de pantalla: la verificación visual la hace el usuario.

## Review Focus

- **cava ausente o sin audio**: si `cava` no existe o no hay salida de audio, `waves.json` puede no existir o quedarse en el último frame. El espectro debe verse igualmente (barras a 0 o congeladas), sin errores QML y sin procesos huérfanos.
- **`waves.json` a medio escribir**: la lectura puede caer en medio de una escritura. Debe descartarse el frame ilegible y seguir con el anterior (`printErrors: false`, `JSON.parse` fallido → no romper).
- **Modo compacto con el menú cerrado y reabierto**: el sampler no debe acumular procesos (`pkill -f "spectrumfeed[.]py"` antes de arrancar) ni quedar vivo en modo normal.
- **Cambio de reproductor en compacto**: al pausar uno y sonar otro, el panel vuelve al automático (comportamiento ya existente) y el espectro debe reflejarlo sin quedarse congelado.
- **Persistencia corrupta o ausente**: `music-panel.json` inexistente, vacío o con JSON inválido debe equivaler a "modo normal", sin fallos de carga.

---

### Task 1: Lógica pura del espectro (`SpectrumMath.js`)

**Files:**
- Create: `modules/music/SpectrumMath.js`
- Create: `tests/support/spectrum_math_harness.js`
- Test: `tests/test_music_spectrum_math.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `SpectrumMath.BARS: number` = 32
  - `SpectrumMath.FACTOR: number` = 0.45
  - `SpectrumMath.levelFromByte(value) -> number` (0..1, no numérico o fuera de rango se recorta)
  - `SpectrumMath.smooth(current, target, factor) -> number`
  - `SpectrumMath.nextLevels(spec, previous, playing, barCount, factor) -> number[]` (longitud `barCount`; con `playing` falso el objetivo es 0 y los niveles decaen)
  - `SpectrumMath.mixColor(from, to, index, count) -> {r, g, b, a}` (para el degradado del tema)

- [ ] **Step 1: Write the failing test**

`tests/test_music_spectrum_math.py`:

```python
"""Contrato de la lógica del espectro del modo compacto de Música.

El mapeo de bytes a niveles, el suavizado y el degradado viven en
``modules/music/SpectrumMath.js``; aquí se ejecuta con node y se comprueba
también el cableado del panel.
"""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "spectrum_math_harness.js"
SPECTRUM_MATH = REPOSITORY_ROOT / "modules" / "music" / "SpectrumMath.js"


@dataclass(frozen=True, slots=True)
class SpectrumCase:
    """Resultado de un escenario del espectro."""

    ok: bool
    detail: str


def run_cases() -> dict[str, SpectrumCase]:
    """Ejecuta los escenarios del espectro y devuelve sus resultados."""
    node = shutil.which("node")
    if node is None:
        pytest.skip("node no disponible")
    result = subprocess.run(  # noqa: S603
        [node, str(HARNESS)],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    assert result.returncode == 0, result.stderr

    cases: dict[str, SpectrumCase] = {}
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        case_id, verdict, detail = parts
        cases[case_id] = SpectrumCase(ok=verdict == "PASS", detail=detail)
    return cases


CASES = run_cases()


def contents(path: Path) -> str:
    """Devuelve el contenido de un archivo del repositorio."""
    return path.read_text(encoding="utf-8")


@pytest.mark.parametrize("case_id", sorted(CASES))
def test_the_spectrum_math_contract(case_id: str) -> None:
    """Cada escenario del espectro debe cumplirse."""
    case = CASES[case_id]

    assert case.ok, case.detail


def test_the_spectrum_math_module_exists() -> None:
    """La lógica del espectro vive en un módulo propio."""
    assert SPECTRUM_MATH.is_file()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_spectrum_math.py -q`
Expected: FAIL — el harness `tests/support/spectrum_math_harness.js` no existe (`assert result.returncode == 0` falla al ejecutar node).

- [ ] **Step 3: Write the harness**

`tests/support/spectrum_math_harness.js` (mismo preámbulo que `art_urls_harness.js`: carga el `.js`, quita `.pragma library`, `vm.createContext`; una línea por caso):

Casos a comprobar (id → aserción):

| id | aserción |
|---|---|
| `byte-zero` | `levelFromByte(0) === 0` |
| `byte-full` | `levelFromByte(255) === 1` |
| `byte-mid` | `Math.abs(levelFromByte(128) - 128/255) < 1e-9` |
| `byte-text` | `levelFromByte("basura") === 0` |
| `byte-negative-clamped` | `levelFromByte(-5) === 0` |
| `byte-over-clamped` | `levelFromByte(999) === 1` |
| `smooth-half` | `smooth(0, 1, 0.45) === 0.45` |
| `smooth-keeps` | `smooth(0.5, 0.5, 0.45) === 0.5` |
| `levels-length` | `nextLevels([], [], true, 32, 0.45).length === 32` |
| `levels-empty-is-zero` | `nextLevels([], [], true, 32, 0.45).every(v => v === 0)` |
| `levels-rises` | con `spec=[255,…]`, `previous` todo 0: primer valor `≈0.45` |
| `levels-decay-when-paused` | `nextLevels([], [1,1], false, 2, 0.45)` → ambos `≈0.55` |
| `levels-short-spec` | `nextLevels([255], [], true, 3, 0.45)` → `[0.45, 0, 0]` |
| `levels-bad-factor` | `nextLevels([255], [], true, 1, 0)` → usa 0.45 (no NaN) |
| `mix-starts-at-from` | `mixColor(from, to, 0, 8)` igual a `from` |
| `mix-ends-at-to` | `mixColor(from, to, 7, 8)` igual a `to` |
| `mix-single-count` | `mixColor(from, to, 0, 1)` no produce NaN |

- [ ] **Step 4: Run test to verify it fails for the right reason**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_spectrum_math.py -q`
Expected: FAIL — node no encuentra `modules/music/SpectrumMath.js` y sale con código ≠ 0.

- [ ] **Step 5: Implement `modules/music/SpectrumMath.js`**

Encabezado `.pragma library`, comentario en español explicando de dónde viene la idea (el `wavefeed.py` del plugin de Noctalia), y las funciones de la sección Interfaces. `nextLevels` recorre `0..barCount-1`, objetivo `playing ? levelFromByte(spec[i]) : 0`, y aplica `smooth` sobre `previous[i]` (0 si falta o no es número). `mixColor` interpola `r/g/b/a` con `t = count > 1 ? index / (count - 1) : 0` y recorta `t` a `[0, 1]`.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_spectrum_math.py -q`
Expected: PASS (todos los casos + el módulo existe).

- [ ] **Step 7: Commit**

```bash
git add modules/music/SpectrumMath.js tests/support/spectrum_math_harness.js tests/test_music_spectrum_math.py
git commit -m "feat: lógica pura del espectro del modo compacto de Música"
```

---

### Task 2: Sampler de cava (`spectrumfeed.py`)

**Files:**
- Create: `modules/music/spectrumfeed.py`
- Test: `tests/test_spectrumfeed.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `spectrumfeed.paths(datadir) -> tuple[str, str, str]` → `(conf, fifo, waves)`
  - `spectrumfeed.cava_config(fifo) -> str` — el texto de configuración de cava
  - `spectrumfeed.running(pattern) -> list[int]`
  - `spectrumfeed.ensure_cava(conf, fifo) -> None`
  - `spectrumfeed.main(datadir) -> None`

- [ ] **Step 1: Write the failing test**

`tests/test_spectrumfeed.py`:

```python
"""Contrato del sampler del espectro del modo compacto de Música.

``spectrumfeed.py`` es una adaptación del ``wavefeed.py`` del plugin de
Noctalia: arranca cava con salida raw a un FIFO y publica 32 valores en
``waves.json``. Se llamó distinto a propósito para que su ``pkill`` no mate
el sampler del plugin.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPOSITORY_ROOT / "modules" / "music" / "spectrumfeed.py"


def load_module() -> ModuleType:
    """Carga el script como módulo sin ejecutar su main."""
    spec = importlib.util.spec_from_file_location("spectrumfeed", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_cava_config_asks_for_32_bars() -> None:
    """El espectro tiene que tener 32 barras."""
    config = load_module().cava_config("/tmp/prueba.fifo")

    assert "bars = 32" in config


def test_the_cava_config_writes_raw_8_bit_to_the_fifo() -> None:
    """La salida es raw, 8 bits, mono, al FIFO indicado."""
    config = load_module().cava_config("/tmp/prueba.fifo")

    assert "method = raw" in config
    assert "raw_target = /tmp/prueba.fifo" in config
    assert "bit_format = 8bit" in config
    assert "channels = mono" in config
    assert "mono_option = average" in config


def test_the_state_files_live_in_the_datadir() -> None:
    """Config, FIFO y waves viven juntos en el datadir pedido."""
    conf, fifo, waves = load_module().paths("/tmp/caparazon-prueba")

    assert conf == "/tmp/caparazon-prueba/cava.conf"
    assert fifo == "/tmp/caparazon-prueba/cava.fifo"
    assert waves == "/tmp/caparazon-prueba/waves.json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_spectrumfeed.py -q`
Expected: FAIL — `modules/music/spectrumfeed.py` no existe (`FileNotFoundError` al cargarlo).

- [ ] **Step 3: Implement `modules/music/spectrumfeed.py`**

Adaptación directa del `wavefeed.py` del plugin de Noctalia
(`~/noctbeats/plugins/mediacontrols/wavefeed.py`), con estos cambios:

- Nombre de fichero `spectrumfeed.py` (el plugin usa `wavefeed.py`); el mismo
  doble `fork` + `setsid` para desvincularse del panel.
- `cava_config(fifo)` extraído como función que **devuelve** el texto (el
  original lo escribía a pelo), con `framerate = 10`, `bars = 32`,
  `autosens = 1`, `sensitivity = 100`, `sleep_timer = 3`, `method = raw`,
  `channels = mono`, `mono_option = average`, `raw_target = <fifo>`,
  `data_format = binary`, `bit_format = 8bit`.
- `paths(datadir)` devuelve `(datadir/cava.conf, datadir/cava.fifo, datadir/waves.json)`.
- `main(datadir)` conserva `BARS = 32`, `RATE = 12`, la guarda de proceso ya
  corriendo (`running(f"spectrumfeed.py {datadir}")`), la lectura por bloques
  del FIFO y la escritura atómica `waves.json.tmp` + `os.replace`.
- `if __name__ == "__main__": main(sys.argv[1])`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_spectrumfeed.py -q`
Expected: PASS.

- [ ] **Step 5: Prueba manual del sampler**

Run:
```bash
rm -f ~/.cache/caparazon/waves.json
setsid --fork python3 ~/Projects/caparazon-shell/modules/music/spectrumfeed.py ~/.cache/caparazon
sleep 3; cat ~/.cache/caparazon/waves.json | head -c 200; echo
pkill -f "spectrumfeed[.]py"
```
Expected: `waves.json` con `{"ts": …, "spec": [32 números]}` (con música sonando, valores > 0; sin audio, cerca de 0). `pgrep -f "spectrumfeed[.]py"` vacío tras el `pkill`.

- [ ] **Step 6: Commit**

```bash
git add modules/music/spectrumfeed.py tests/test_spectrumfeed.py
git commit -m "feat: sampler de cava para el espectro del modo compacto"
```

---

### Task 3: Persistencia del modo (`MusicSettings.qml`)

**Files:**
- Create: `modules/music/MusicSettings.qml`
- Test: `tests/test_music_compact.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `MusicSettings.compact: bool` (propiedad escribible; leer guarda)
  - `MusicSettings.loaded: bool`
  - `MusicSettings.settingsPath: string`
  - `MusicSettings.save(): void`

- [ ] **Step 1: Write the failing test**

`tests/test_music_compact.py`:

```python
"""Contrato del modo compacto de la categoría Música.

El panel oculta letra, barra y botones, deja el álbum con el vinilo, pone un
espectro al pie y recuerda la elección. Aquí se comprueba el cableado
estático de los ficheros QML, como en ``test_music_art.py``.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MUSIC_PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "MusicPanel.qml"
MUSIC_SETTINGS = REPOSITORY_ROOT / "modules" / "music" / "MusicSettings.qml"
SPECTRUM = REPOSITORY_ROOT / "modules" / "music" / "Spectrum.qml"


def contents(path: Path) -> str:
    """Devuelve el contenido de un archivo del repositorio."""
    return path.read_text(encoding="utf-8")


def test_the_settings_file_exists() -> None:
    """El modo se recuerda en un servicio propio."""
    assert MUSIC_SETTINGS.is_file()


def test_the_settings_live_in_the_caparazon_cache() -> None:
    """El estado vive junto al resto de la caché de Caparazón."""
    settings = contents(MUSIC_SETTINGS)

    assert "/.cache/caparazon" in settings
    assert "music-panel.json" in settings


def test_the_settings_expose_and_persist_compact() -> None:
    """El servicio expone `compact`, lo lee y lo guarda."""
    settings = contents(MUSIC_SETTINGS)

    assert "property bool compact" in settings
    assert "JsonAdapter" in settings
    assert "function save(" in settings


def test_the_settings_write_atomically() -> None:
    """Se escribe a un .tmp y se renombra, como el resto del repo."""
    settings = contents(MUSIC_SETTINGS)

    assert ".tmp" in settings
    assert "mv " in settings
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_compact.py -q`
Expected: FAIL — `modules/music/MusicSettings.qml` no existe.

- [ ] **Step 3: Implement `modules/music/MusicSettings.qml`**

`Item` invisible (`visible: false`), con:

- `readonly property string settingsDir: Quickshell.env("HOME") + "/.cache/caparazon"`
- `readonly property string settingsPath: settingsDir + "/music-panel.json"`
- `property bool compact: false`, `property bool loaded: false`
- `onCompactChanged: save()`
- `function save()`: si `!loaded`, sale (evita reescribir durante la carga);
  si no, lanza un `Process` con `["bash", "-c", "printf '%s\\n' \"$1\" > \"$2\".tmp && mv \"$2\".tmp \"$2\"", "bash", JSON.stringify({compact: root.compact}), root.settingsPath]`.
- `Process` de arranque que crea el directorio y el fichero si falta
  (`mkdir -p`; `[ -f ] || printf '{"compact":false}'`), y en `onExited`
  recarga el `FileView`.
- `FileView` con `path: settingsPath`, `watchChanges: true`,
  `printErrors: false`, `onFileChanged: reload()` y un `JsonAdapter` con
  `property bool compact: false` (esto es lo que comprueba el test del
  `JsonAdapter`).
- Al terminar la primera carga: `root.compact = adapter.compact` y **después**
  `root.loaded = true` (para que esa asignación no se guarde de vuelta).
  Un JSON inválido deja `compact` en `false` sin errores.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_compact.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/music/MusicSettings.qml tests/test_music_compact.py
git commit -m "feat: persistencia del modo compacto de Música"
```

---

### Task 4: Componente del espectro (`Spectrum.qml`)

**Files:**
- Create: `modules/music/Spectrum.qml`
- Test: `tests/test_music_compact.py` (se añaden casos)

**Interfaces:**
- Consumes: `SpectrumMath.js` (Task 1), `~/.cache/caparazon/waves.json` (Task 2), `Theme` (`m3Primary`, `m3Tertiary`).
- Produces:
  - `Spectrum.active: bool` — visible/activo; arranca y para el sampler
  - `Spectrum.playing: bool` — puerta de los niveles (en pausa decaen a 0)
  - `Spectrum.barCount: int` (32)
  - `Spectrum.levels: var` (niveles suavizados, sólo lectura para el resto)

- [ ] **Step 1: Write the failing test**

Añadir a `tests/test_music_compact.py`:

```python
def test_the_spectrum_component_exists() -> None:
    """El espectro es un componente propio y reutilizable."""
    assert SPECTRUM.is_file()


def test_the_spectrum_uses_the_shared_math() -> None:
    """El dibujo no reimplementa el suavizado."""
    spectrum = contents(SPECTRUM)

    assert 'import "SpectrumMath.js" as SpectrumMath' in spectrum
    assert "SpectrumMath.nextLevels(" in spectrum


def test_the_spectrum_reads_the_waves_file() -> None:
    """El espectro lee el JSON que publica el sampler."""
    spectrum = contents(SPECTRUM)

    assert "waves.json" in spectrum
    assert "FileView" in spectrum
    assert "watchChanges: true" in spectrum


def test_the_spectrum_starts_and_stops_the_sampler() -> None:
    """El sampler sólo vive mientras el espectro está activo."""
    spectrum = contents(SPECTRUM)

    assert "spectrumfeed.py" in spectrum
    assert 'spectrumfeed[.]py' in spectrum


def test_the_spectrum_follows_the_theme() -> None:
    """El degradado sale de los colores del tema."""
    spectrum = contents(SPECTRUM)

    assert "Theme.m3Primary" in spectrum
    assert "Theme.m3Tertiary" in spectrum
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_compact.py -q`
Expected: FAIL — `modules/music/Spectrum.qml` no existe.

- [ ] **Step 3: Implement `modules/music/Spectrum.qml`**

`Item` con:

- imports: `Quickshell`, `Quickshell.Io`, `QtQuick`, `"../../theme"`, `"SpectrumMath.js" as SpectrumMath`.
- propiedades `active: false`, `playing: false`, `barCount: 32`,
  `property var levels: []`.
- `Process` que arranca el sampler con
  `["python3", Quickshell.shellPath("modules/music/spectrumfeed.py"), Quickshell.env("HOME") + "/.cache/caparazon"]`
  y otro `Process` que lo para con `["pkill", "-f", "spectrumfeed[.]py"]`;
  `onActiveChanged`: activo → arranca, inactivo → para.
- `FileView` (`watchChanges: true`, `printErrors: false`, `onFileChanged: reload()`)
  sobre `~/.cache/caparazon/waves.json` con `JsonAdapter` de
  `property var spec: []`.
- `Timer` a `interval: 83` (~12 fps) con `running: root.active` que hace
  `root.levels = SpectrumMath.nextLevels(wavesAdapter.spec, root.levels, root.playing, root.barCount, SpectrumMath.FACTOR)`.
- Dibujo: un `Row` con márgenes laterales de 16 y `spacing: 3`, y un
  `Repeater { model: root.barCount }` de `Rectangle` anclados abajo
  (`height: Math.max(2, level * parent.height)`, `radius: Math.min(2, width / 2)`)
  con `color: ` el resultado de `SpectrumMath.mixColor(Theme.m3Primary, Theme.m3Tertiary, index, root.barCount)`.
- Comentario en español explicando que el sampler sólo corre en modo compacto.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_compact.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/music/Spectrum.qml tests/test_music_compact.py
git commit -m "feat: componente del espectro del modo compacto"
```

---

### Task 5: Modo compacto en el panel (botón, ocultar, espectro al pie)

**Files:**
- Modify: `modules/secondmenu/MusicPanel.qml`

**Interfaces:**
- Consumes: `MusicSettings` (Task 3), `Spectrum` (Task 4), `IconResolver` (`modules/icons`), `Theme`.
- Produces (para Task 6): `root.compact: bool` (readonly, viene de `MusicSettings`), `root.toggleCompact(): void`.

- [ ] **Step 1: Write the failing test**

Añadir a `tests/test_music_compact.py`:

```python
def test_the_panel_hides_the_controls_in_compact_mode() -> None:
    """En compacto desaparecen la barra de progreso y los botones."""
    panel = contents(MUSIC_PANEL)

    assert "root.compact" in panel
    assert "controlsCard" in panel
    assert "visible: !root.compact" in panel


def test_the_panel_hides_the_lyrics_in_compact_mode() -> None:
    """En compacto desaparece la letra."""
    panel = contents(MUSIC_PANEL)

    lyrics_block = panel.split("id: lyricsCard", 1)[1].split("id: lyricsList", 1)[0]
    assert "root.compact" in lyrics_block


def test_the_panel_puts_the_spectrum_at_the_bottom() -> None:
    """El espectro es el pie del panel, no va entre el álbum y el título."""
    panel = contents(MUSIC_PANEL)

    assert "Spectrum {" in panel
    assert "active: root.compact" in panel
    discs_block = panel.split("id: discs", 1)[1].split("id: lyricsCard", 1)[0]
    assert "Spectrum {" not in discs_block


def test_the_panel_has_the_compact_button() -> None:
    """El botón ⛶ alterna el modo y usa un icono del tema."""
    panel = contents(MUSIC_PANEL)

    assert "toggleCompact" in panel
    assert "view-fullscreen" in panel
    assert "window-restore" in panel
    assert "IconResolver.firstOf(" in panel


def test_the_panel_uses_the_settings_service() -> None:
    """El modo del panel sale del servicio que lo recuerda."""
    panel = contents(MUSIC_PANEL)

    assert 'import "../music"' in panel
    assert "MusicSettings {" in panel
    assert "compactSettings.compact" in panel


def test_the_panel_keeps_the_album_visible_in_compact_mode() -> None:
    """El álbum no se sustituye: sigue ahí con el vinilo."""
    panel = contents(MUSIC_PANEL)

    assert "id: discs" in panel
    assert "id: vinyl" in panel
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_compact.py -q`
Expected: FAIL — `MusicPanel.qml` aún no menciona `root.compact` ni `Spectrum`.

- [ ] **Step 3: Implementar en `MusicPanel.qml`**

- Imports nuevos: `"../music"`, `"../icons"`, `QtQuick.Effects`.
- Servicio y estado:
  ```qml
  MusicSettings { id: compactSettings }
  readonly property bool compact: compactSettings.compact
  function toggleCompact() { compactSettings.compact = !compactSettings.compact; }
  ```
- Ocultar: `controlsCard.visible: !root.compact`; la `lyricsCard` ya usa
  `visible: opacity > 0` → añadir `&& !root.compact`; y el ancho del `stage`
  pasa a `root.hasLyrics && !root.compact ? Math.round(body.width * 0.5) : body.width`.
- Alto del cuerpo:
  ```qml
  height: layout.height - (root.compact ? spectrum.height : controlsCard.height) - layout.spacing
  ```
- Espectro al pie, como último hijo de `layout` (después de `controlsCard`):
  ```qml
  Spectrum {
      id: spectrum
      width: layout.width
      height: root.compact ? 64 : 0
      visible: root.compact
      active: root.compact
      playing: root.playing
  }
  ```
- Botón ⛶, último hijo de `root` para quedar por encima de todo (`z: 10`),
  28×28 anclado arriba a la derecha con margen 8: `Rectangle` circular
  (`radius: 14`, `color: Theme.chip`, borde `Theme.hairline`) + `IconImage`
  con `implicitSize: 16` y
  `source: IconResolver.firstOf(root.compact ? ["window-restore-symbolic", "window-restore"] : ["view-fullscreen-symbolic", "view-fullscreen"])`,
  tintado con `layer.enabled: true` + `MultiEffect { colorization: 1.0; colorizationColor: btnHover.hovered ? Theme.text : Theme.textDim }`;
  `HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }`,
  `MouseArea` que llama `root.toggleCompact()`, y
  `opacity: btnHover.hovered ? 1.0 : 0.55` con `Behavior on opacity`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_compact.py -q`
Expected: PASS.

- [ ] **Step 5: Verificar que QML carga**

Run:
```bash
pkill -f 'quickshell -p'; sleep 1
setsid --fork quickshell -p ~/Projects/caparazon-shell -d > /tmp/opencode/qs.log 2>&1
sleep 5; grep -iE "error|not a type|is not defined|Failed to load" /tmp/opencode/qs.log || echo "sin errores"
```
Expected: `sin errores` y `Configuration Loaded` en el log.

- [ ] **Step 6: Commit**

```bash
git add modules/secondmenu/MusicPanel.qml tests/test_music_compact.py
git commit -m "feat: modo compacto con espectro en la categoría Música"
```

---

### Task 6: Clic en el álbum = play/pausa

**Files:**
- Modify: `modules/secondmenu/MusicPanel.qml`

**Interfaces:**
- Consumes: `root.compact` y `root.toggleCompact()` (Task 5); `root.player`,
  `root.hasPlayer` (ya existentes).
- Produces: nada nuevo.

- [ ] **Step 1: Write the failing test**

Añadir a `tests/test_music_compact.py`:

```python
def test_the_album_toggles_playback_on_click() -> None:
    """Un clic en el álbum pausa o reanuda, en los dos modos."""
    panel = contents(MUSIC_PANEL)

    discs_block = panel.split("id: discs", 1)[1].split("id: lyricsCard", 1)[0]
    assert "togglePlaying()" in discs_block
    assert "canTogglePlaying" in discs_block


def test_the_album_click_does_not_eat_the_wheel() -> None:
    """El clic convive con la rueda que cambia de reproductor."""
    panel = contents(MUSIC_PANEL)

    discs_block = panel.split("id: discs", 1)[1].split("id: lyricsCard", 1)[0]
    assert "WheelHandler" in discs_block
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_compact.py -q`
Expected: FAIL — el bloque `discs` no llama a `togglePlaying()`.

- [ ] **Step 3: Implementar en `MusicPanel.qml`**

Dentro de `discs`, como último hijo (para recibir el clic por encima del
álbum y del vinilo):

```qml
// Clic en el álbum = pausa/reanuda. En compacto es la única forma de
// parar la música, porque los botones desaparecen.
MouseArea {
    anchors.fill: parent
    enabled: root.hasPlayer && root.player.canTogglePlaying
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: root.player.togglePlaying()
}
```

Y quitar `cursorShape: Qt.ArrowCursor` del `HoverHandler` de `discs` (que
ahora teñiría el cursor sobre el álbum): el cursor lo fija el `MouseArea`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Projects/caparazon-shell && uv run pytest tests/test_music_compact.py -q`
Expected: PASS.

- [ ] **Step 5: Suite completa, lint y arranque**

Run:
```bash
cd ~/Projects/caparazon-shell
uv run pytest -q
uv run ruff check tests
uv run ruff format --check tests/test_music_compact.py tests/test_music_spectrum_math.py tests/test_spectrumfeed.py
pkill -f 'quickshell -p'; sleep 1
setsid --fork quickshell -p ~/Projects/caparazon-shell -d > /tmp/opencode/qs.log 2>&1
sleep 5; grep -iE "error|not a type|is not defined|Failed to load" /tmp/opencode/qs.log || echo "sin errores"
```
Expected: toda la suite pasa (190 + los nuevos), ruff limpio, sin errores en el log.

- [ ] **Step 6: Commit**

```bash
git add modules/secondmenu/MusicPanel.qml tests/test_music_compact.py
git commit -m "feat: clic en el álbum para pausar y reanudar"
```

---

### Task 7: Verificación real, README y limpieza

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: nada.

- [ ] **Step 1: Verificación con el usuario**

Pedir al usuario que abra el menú secundario en Música y compruebe:

1. El botón ⛶ arriba a la derecha alterna el modo.
2. En compacto: álbum con el vinilo girando, título y artista debajo, espectro
   al pie y nada de letra, barra ni botones.
3. El espectro se mueve con la música y se tiñe con el color del tema.
4. Clic en el álbum pausa y reanuda; la rueda sigue cambiando de reproductor.
5. Cerrar el menú y reabrirlo conserva el modo.
6. Reiniciar la shell conserva el modo.
7. Cerrar el menú estando en compacto y comprobar `pgrep -f spectrumfeed`
   vacío (el sampler no queda vivo).

Iterar sobre lo que el usuario vea raro (es el único juez visual: este plan no
toma capturas).

- [ ] **Step 2: Actualizar el README**

Añadir a la lista de características (donde se describe el menú secundario) una
línea con el modo compacto: álbum con el vinilo girando, espectro de cava teñido
con el tema al pie, y la elección recordada entre aperturas.

- [ ] **Step 3: Comprobar que no quedan restos**

Run:
```bash
pgrep -af 'spectrumfeed|cava -p' || echo "sin procesos de espectro"
git status --short
```
Expected: sin procesos del sampler cuando el modo está apagado; el árbol sólo
con `README.md` modificado.

- [ ] **Step 4: Commit y push**

```bash
git add README.md
git commit -m "docs: modo compacto de Música en el README"
git push origin main
```

---

## Autoevaluación del plan

**Cobertura de la especificación:**

| Punto del diseño | Tarea |
|---|---|
| `spectrumfeed.py` (cava → waves.json) | Task 2 |
| `Spectrum.qml` (FileView + barras) | Task 4 |
| `SpectrumMath.js` + harness | Task 1 |
| `MusicSettings.qml` (persistencia) | Task 3 |
| Botón ⛶ (view-fullscreen / window-restore) | Task 5 |
| Ocultar letra, barra y botones | Task 5 |
| Espectro al pie (no entre álbum y título) | Task 5 |
| Álbum + vinilo intactos | Task 5 (test de regresión) |
| Clic en el álbum = play/pausa | Task 6 |
| Rueda intacta | Task 6 (test de regresión) |
| Degradado del tema | Task 1 + Task 4 |
| Sampler sólo en compacto | Task 4 + Task 7 |
| Colores/valores del espectro | Task 1 + Task 2 |

**Consistencia de tipos:** `SpectrumMath.nextLevels(spec, previous, playing, barCount, factor)`
se usa igual en Task 1 (tests), Task 4 (implementación) y el componente;
`MusicSettings.compact` y `root.toggleCompact()` de Task 5 son los que consume
Task 6; `Spectrum.active`/`playing` se definen en Task 4 y se cablean en Task 5.

**Revisión de los "Review Focus":** cava ausente → Task 2 (paso manual) y
Task 4 (`printErrors: false`); JSON a medio escribir → Task 3 y Task 4;
procesos acumulados → Task 4 (`pkill` antes de arrancar) y Task 7 (paso 3);
cambio de reproductor → comportamiento existente + Task 7 (paso 1.4);
persistencia corrupta → Task 3 (`compact` queda en `false` si el JSON falla).

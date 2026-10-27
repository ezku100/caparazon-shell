# Vigilante del tema de iconos y limpieza de `networkIcon` — Plan de implementación

> **Para trabajadores agénticos:** SUB-SKILL OBLIGATORIA: usa `superpowers:subagent-driven-development` (recomendado) o `superpowers:executing-plans` para implementar este plan tarea por tarea. Los pasos usan casillas (`- [ ]`) para seguir el progreso.

**Objetivo:** Que la shell reinicie sola cuando cambia el tema de iconos de KDE, y que desaparezca la cadena muerta de `networkIcon`.

**Arquitectura:** Toda la lógica de decisión vive en JavaScript plano (`IconTheme.js`), igual que `IconNames.js`, y se prueba con node desde pytest: leer el tema, decidir si hay que reiniciar y construir el comando de reinicio. El QML (`IconThemeWatcher.qml`) es sólo cableado: vigila `kdeglobals` con `FileView` + `FileSystemWatcher`, aplica un debounce de 500 ms y llama a lo que diga el JavaScript. El reinicio se decide según dónde corra la shell: con systemd, una unidad transitoria que reinicia la unidad de la shell; sin systemd, relanzando el `argv` original.

**Stack:** QML / Quickshell 0.3.2, QtQuick (`FileSystemWatcher`), JavaScript plano (QML + node), pytest, ruff, basedpyright.

**Spec:** `docs/superpowers/specs/2026-10-27-vigilante-tema-iconos-design.md` — el plan razona a partir del spec; quien ejecute, lee ambos.

## Desviaciones respecto al plan

El plan se escribió antes de tocar el código; al ejecutarlo aparecieron cuatro
desviaciones, todas comprobadas contra el sistema real. El spec ya refleja el
resultado final.

1. **No hay `FileSystemWatcher` en Quickshell 0.3.2** ("FileSystemWatcher is
   not a type"). La vigilancia queda en `FileView` con `watchChanges: true`,
   que aguanta la sustitución atómica de KConfig, y la red de seguridad es un
   temporizador de sondeo de 5 s en vez de un watcher sobre el directorio.
2. **La unidad se deduce del último tramo del cgroup**, no de cualquier
   `.service`: los tramos anteriores incluyen `user@1000.service`, y
   reiniciar el gestor de usuario cerraría la sesión entera. Se descartan
   `user-*` e `init.service`.
3. **El relanzamiento manual mata al proceso actual** (`SIGTERM`) antes de
   reejecutar el `argv`. El plan sólo esperaba a que el PID desapareciera y
   nadie lo mataba, así que la shell no se reiniciaba nunca.
4. **`TimeoutExpired.stdout` guarda bytes en POSIX** aunque se pida
   `text=True`; el snippet de la tarea 3 tiene que decodificarlo.

## Restricciones globales

- Cero dependencias nuevas: nada de instalar paquetes, ni de añadir imports fuera de `QtQuick`, `Quickshell`, `Quickshell.Io` y JavaScript plano.
- Los iconos se resuelven **por nombre de tema**, nunca por ruta absoluta de un tema concreto.
- El reinicio ocurre **sólo** si `[Icons] Theme` pasa a un valor no vacío distinto del anterior.
- Nada se reinicia al arrancar: el primer valor observado es la línea base.
- La lógica de decisión (leer, decidir, construir el comando) vive en el JavaScript y se prueba con node; el QML no decide nada.
- Commits en español **sin tildes**. Rama `feature/vigilante-tema-iconos`, merge `--no-ff` a `main`, push a `origin/main`.
- Puerta de calidad antes de dar el trabajo por terminado: `uv run pytest -q` (los 29 tests existentes más los nuevos, todos en verde), `uv run ruff check .` sin avisos, `uv run basedpyright` sin errores.
- Si `node` no está instalado, los tests del parser se saltan (`pytest.skip`), como ya hace `tests/test_icon_names.py`.
- Los comentarios y el código pueden llevar tildes; los mensajes de commit, no.

## Foco de revisión

Las cinco entradas o condiciones que el spec sugiere pero ningún test cubre de forma automática, ordenadas por probabilidad de morder. Cada una tiene su prueba asignada:

1. **`kdeglobals` escrito a medias**: KConfig lo reescribe en varias pasadas y una lectura a medio escribir puede devolver la sección `[Icons]` sin la clave `Theme`. Comportamiento esperado: no reiniciar con un valor vacío ni inventarse un tema. → Tarea 1, casos `missing_key_gives_empty` y `empty_value_keeps_the_previous_theme`.
2. **Sustitución atómica del archivo**: KConfig escribe en un temporal y renombra, con lo que un inotify sobre el fichero queda obsoleto. Comportamiento esperado: el watcher sigue detectando cambios. → Tarea 2, el `FileSystemWatcher` sobre el directorio; Tarea 4, el cambio en vivo se hace con `mv`.
3. **Cambio de tema durante el arranque de la shell**: la shell arranca con un tema y el watcher lee otro. Comportamiento esperado: no reiniciar en bucle; la línea base es el primer valor observado. → Tarea 1, caso `first_observed_theme_is_only_a_baseline`.
4. **`systemd-run` no disponible** en el sistema. Comportamiento esperado: caer a `systemctl --user restart` y reiniciar igual. → Tarea 1, caso `the_restart_command_falls_back_to_systemctl`; Tarea 2, el script shell decide en tiempo de ejecución con `command -v`.
5. **La shell corre sin systemd** (arranque manual en desarrollo). Comportamiento esperado: relanzar el mismo `argv` cuando el PID actual muera, en lugar de no hacer nada. → Tarea 1, caso `the_relaunch_command_waits_for_the_pid`; Tarea 4, comprobación en vivo con una sonda aislada.

## Estructura de archivos

| Archivo | Responsabilidad |
| --- | --- |
| `modules/icons/IconTheme.js` (nuevo) | Leer `[Icons] Theme`, decidir si hay que reiniciar y construir el comando de reinicio. JavaScript puro, sin estado. |
| `modules/icons/IconThemeWatcher.qml` (nuevo) | Vigilar `kdeglobals`, aplicar el debounce y pedir el reinicio. No decide: pregunta a `IconTheme.js`. |
| `modules/icons/qmldir` (modificar) | Declarar el tipo nuevo para que se pueda importar. |
| `shell.qml` (modificar) | Instanciar el vigilante una sola vez; quitar el paso de `networkIcon`. |
| `modules/bar/resource-monitor.sh` (modificar) | Quitar el cálculo de `net_icon` y el séptimo campo. |
| `modules/bar/ResourceMonitorService.qml` (modificar) | Quitar la propiedad `networkIcon` y ajustar el mínimo de campos. |
| `modules/bar/Bar.qml` (modificar) | Quitar la propiedad `networkIcon` y su paso al monitor. |
| `modules/bar/ResourceMonitor.qml` (modificar) | Quitar la propiedad `networkIcon`, que no se usaba. |
| `tests/support/icon_theme_harness.js` (nuevo) | Escenarios del módulo con node, en el mismo formato que `icon_names_harness.js`. |
| `tests/test_icon_theme.py` (nuevo) | Contrato pytest del módulo, en el mismo formato que `test_icon_names.py`. |
| `tests/test_icon_theme_watcher.py` (nuevo) | Contrato del cableado: el vigilante se instancia una vez y no decide por su cuenta. |
| `tests/test_resource_monitor_output.py` (nuevo) | El script de muestreo entrega seis campos. |
| `README.md` (modificar) | Documentar el reinicio automático. |

## Preparación

- [ ] **Paso 1: Crear la rama de trabajo**

```bash
git switch -c feature/vigilante-tema-iconos
```

Esperado: `git status` muestra la rama `feature/vigilante-tema-iconos` y el árbol limpio.

- [ ] **Paso 2: Subir el spec y el plan**

```bash
git add docs/superpowers
git commit -m "Documenta el vigilante del tema de iconos"
```

Esperado: commit nuevo con los dos documentos.

---

### Tarea 1: Módulo del tema de iconos

**Archivos:**
- Crear: `modules/icons/IconTheme.js`
- Crear: `tests/support/icon_theme_harness.js`
- Crear: `tests/test_icon_theme.py`

**Interfaces:**
- Consume: nada.
- Produce: cuatro funciones de JavaScript plano, importables desde QML con `import "IconTheme.js" as IconTheme` y ejecutables con node:
  - `iconTheme(text: string) -> string` — valor de la clave `Theme` de la sección `[Icons]`, o `""` si no está.
  - `themeDecision(previous: string, current: string, baselineKnown: boolean) -> { theme: string, restart: boolean }` — el tema que queda como referencia y si hay que reiniciar.
  - `restartCommand(unit: string) -> string[]` — el `argv` que reinicia la unidad de la shell.
  - `relaunchCommand(pid: number, argv: string[]) -> string[]` — el `argv` que relanza la shell cuando el PID actual muera.

- [ ] **Paso 1: Escribir los escenarios que fallan**

Crear `tests/support/icon_theme_harness.js` con la misma forma que `tests/support/icon_names_harness.js`: carga `modules/icons/IconTheme.js` con `vm.runInContext` desde `vm.createContext({})`, saca `iconTheme`, `themeDecision`, `restartCommand` y `relaunchCommand` del contexto, y escribe por stdout un JSON `{"cases": [{"id", "name", "ok", "detail"}]}`.

Casos, con su llamada exacta:

| id | llamada | esperado |
| --- | --- | --- |
| `theme_is_read_from_the_icons_section` | `iconTheme("[Icons]\nTheme=Tela-dark\n")` | `"Tela-dark"` |
| `value_is_trimmed` | `iconTheme("[Icons]\nTheme=  Tela-dark  \n")` | `"Tela-dark"` |
| `missing_section_gives_empty` | `iconTheme("[KDE]\nLookAndFeelPackage=org.pikaos.breeze-theme\n")` | `""` |
| `missing_key_gives_empty` | `iconTheme("[Icons]\n")` | `""` |
| `empty_text_gives_empty` | `iconTheme("")` | `""` |
| `other_sections_are_ignored` | `iconTheme("[KDE]\nTheme=Otro\n")` | `""` |
| `comments_are_ignored` | `iconTheme("# comentario\n[Icons]\n; otro comentario\nTheme=breeze\n")` | `"breeze"` |
| `theme_stops_at_the_next_section` | `iconTheme("[Icons]\nTheme=Tela-dark\n[KDE]\nTheme=breeze\n")` | `"Tela-dark"` |
| `a_new_theme_asks_for_a_restart` | `themeDecision("Tela-dark", "breeze", true)` | `{ theme: "breeze", restart: true }` |
| `the_same_theme_keeps_the_shell` | `themeDecision("Tela-dark", "Tela-dark", true)` | `{ theme: "Tela-dark", restart: false }` |
| `empty_value_keeps_the_previous_theme` | `themeDecision("Tela-dark", "", true)` | `{ theme: "Tela-dark", restart: false }` |
| `first_observed_theme_is_only_a_baseline` | `themeDecision("", "breeze", false)` | `{ theme: "breeze", restart: false }` |
| `a_theme_that_appears_later_asks_for_a_restart` | `themeDecision("", "breeze", true)` | `{ theme: "breeze", restart: true }` |
| `the_restart_command_uses_a_transient_unit` | `restartCommand("app-caparazon@autostart.service")` | `argv[0] === "sh"`, el script contiene `systemd-run --user --on-active=0.3`, y la unidad va como argumento, no dentro del script |
| `the_restart_command_falls_back_to_systemctl` | `restartCommand("app-caparazon@autostart.service")` | el script contiene `command -v systemd-run` y, en la alternativa, `systemctl --user restart` |
| `the_relaunch_command_waits_for_the_pid` | `relaunchCommand(4242, ["quickshell", "-p", "/home/u/shell"])` | `argv[0] === "sh"`, el script contiene `kill -0 4242`, y las tres últimas entradas son las del `argv` original |

- [ ] **Paso 2: Ejecutar los escenarios y ver que fallan**

Correr: `node tests/support/icon_theme_harness.js`

Esperado: falla con `no se pudo cargar .../IconTheme.js` o con `context.iconTheme is not a function`, porque el módulo todavía no existe.

- [ ] **Paso 3: Implementar `modules/icons/IconTheme.js`**

Cuatro funciones y nada más:

- `iconTheme(text)`: recorre las líneas del texto, recuerda la sección actual y sólo mira la clave `Theme` mientras la sección sea `[Icons]`. La comparación de sección y clave ignora mayúsculas y espacios alrededor; el valor va recortado y sin comillas. Una sección que empieza por `[` cierra la anterior.
- `themeDecision(previous, current, baselineKnown)`: si `current` está vacío, devuelve `{ theme: previous, restart: false }`. Si `baselineKnown` es falso, devuelve `{ theme: current, restart: false }` (la línea base no reinicia). Si `current` es distinto de `previous`, devuelve `{ theme: current, restart: true }`; si no, `{ theme: previous, restart: false }`.
- `restartCommand(unit)`: devuelve `["sh", "-c", <script>, "caparazon-reload", unit]`, con `<script>` = `command -v systemd-run >/dev/null 2>&1 && systemd-run --user --on-active=0.3 --unit=caparazon-icon-theme-reload systemctl --user restart "$1" || systemctl --user restart "$1"`. La unidad viaja como `$1`, nunca pegada al script: así no hay problemas de comillas.
- `relaunchCommand(pid, argv)`: devuelve `["sh", "-c", <script>, "caparazon-relaunch", ...argv]`, con `<script>` = `while kill -0 <pid> 2>/dev/null; do sleep 0.2; done; exec "$@"`.

El archivo lleva `pragma library` y sigue el estilo de `modules/icons/IconNames.js`: `var`, comentarios en español, sin estado global.

- [ ] **Paso 4: Ejecutar los escenarios y ver que pasan**

Correr: `node tests/support/icon_theme_harness.js`

Esperado: sale un JSON con los quince casos en `"ok": true` y el proceso termina con código 0.

- [ ] **Paso 5: Escribir el contrato pytest**

Crear `tests/test_icon_theme.py` con la misma forma que `tests/test_icon_names.py`: `run_cases()` ejecuta el harness con node (salta con `pytest.skip` si no hay node), `assert_case(cases, case_id)` falla si el caso no está o no está en verde, y un test por comportamiento:

- `test_the_icon_theme_is_read_from_the_icons_section`
- `test_a_missing_section_or_key_gives_no_theme`
- `test_other_sections_and_comments_are_ignored`
- `test_a_new_theme_asks_for_a_restart`
- `test_the_same_or_an_empty_theme_keeps_the_shell`
- `test_the_first_observed_theme_is_only_a_baseline`
- `test_the_restart_command_prefers_a_transient_unit`
- `test_the_restart_command_falls_back_to_systemctl`
- `test_the_relaunch_command_waits_for_the_pid`

- [ ] **Paso 6: Ejecutar pytest y ver que pasa**

Correr: `uv run pytest tests/test_icon_theme.py -q`

Esperado: `9 passed`.

- [ ] **Paso 7: Commit**

```bash
git add modules/icons/IconTheme.js tests/support/icon_theme_harness.js tests/test_icon_theme.py
git commit -m "Iconos: decide el cambio de tema y el comando de reinicio"
```

---

### Tarea 2: Vigilante del tema de iconos

**Archivos:**
- Crear: `modules/icons/IconThemeWatcher.qml`
- Modificar: `modules/icons/qmldir`
- Modificar: `shell.qml` (import e instanciación)
- Crear: `tests/test_icon_theme_watcher.py`

**Interfaces:**
- Consume: `IconTheme.iconTheme`, `IconTheme.themeDecision`, `IconTheme.restartCommand` e `IconTheme.relaunchCommand` de la Tarea 1.
- Produce: el tipo QML `IconThemeWatcher`, importable con `import "modules/icons"`, que no expone nada al resto de la shell: sólo se instancia y vigila.

- [ ] **Paso 1: Escribir el contrato que falla**

Crear `tests/test_icon_theme_watcher.py`, con el estilo de `tests/test_theme_install_contract.py` (lee el texto de los archivos y comprueba lo pactado):

- `test_the_watcher_is_declared_for_import`: `modules/icons/qmldir` contiene una línea `IconThemeWatcher 1.0 IconThemeWatcher.qml`.
- `test_the_shell_starts_exactly_one_watcher`: en `shell.qml` aparece exactamente una vez `IconThemeWatcher {`.
- `test_the_watcher_delegates_the_decision`: `modules/icons/IconThemeWatcher.qml` menciona `IconTheme.themeDecision` y `IconTheme.iconTheme`, y no compara el valor del tema por su cuenta.
- `test_the_watcher_waits_before_reading`: el fichero declara un `Timer` con `interval: 500`.
- `test_the_watcher_reads_the_process_state`: el fichero lee `/proc/self/cgroup` y `/proc/$PPID/cmdline`.

- [ ] **Paso 2: Ejecutar el contrato y ver que falla**

Correr: `uv run pytest tests/test_icon_theme_watcher.py -q`

Esperado: `5 failed` (el vigilante todavía no existe).

- [ ] **Paso 3: Crear `modules/icons/IconThemeWatcher.qml`**

Un `Item` con `visible: false`, como los demás servicios de la shell. Estructura y nombres exactos:

- `readonly property string configDir`: `XDG_CONFIG_HOME` si tiene contenido, si no `HOME + "/.config"`.
- `readonly property string configFile`: `configDir + "/kdeglobals"`.
- `property string currentTheme: ""` — el último tema conocido.
- `property bool baselineKnown: false` — si ya se ha observado un tema real.
- `property bool restarting: false` — evita encolar dos reinicios.

Piezas:

- `FileView` de `Quickshell.Io` con `path: configFile`, `watchChanges: true`, `printErrors: false`; en `onFileChanged` llama a `scheduleCheck()`.
- `FileSystemWatcher` de `QtQuick` con `paths: [configDir]`; en `onDirectoryChanged` llama a `scheduleCheck()`. Es la red de seguridad por si KConfig sustituye el fichero de forma atómica.
- `Timer` con `interval: 500`; `scheduleCheck()` lo rearranca y `onTriggered` llama a `checkTheme()`.
- `checkTheme()`: lee el texto del `FileView`, calcula `IconTheme.iconTheme(texto)` y llama a `applyTheme(valor)`.
- `applyTheme(valor)`: llama a `IconTheme.themeDecision(currentTheme, valor, baselineKnown)` y guarda `decision.theme` en `currentTheme` y `baselineKnown` a verdadero; si `decision.restart` es verdadero, llama a `requestRestart()`.
- `requestRestart()`: si `restarting` es verdadero, no hace nada; si no, lo pone a verdadero y llama a `restart()`.

El reinicio:

- Un `Process` con `command: ["sh", "-c", <script>]`, donde `<script>` imprime tres cosas separadas por líneas: `PID=<n>` con `$PPID` (el PID de la shell), `UNIT=<ruta del cgroup>` con `tr '\\0' '\\n' < /proc/self/cgroup | tail -n 1`, y `ARGV` seguido de una línea por entrada de `tr '\\0' '\\n' < /proc/$PPID/cmdline`. El `PPID` es el proceso de Quickshell porque `Process` lanza el comando como hijo directo.
- Al terminar el `Process`, se lee la salida: el componente de la línea `UNIT=` cuyo último tramo termine en `.service` es el nombre de la unidad.
- Con unidad: `Quickshell.execDetached(IconTheme.restartCommand(unidad))`.
- Sin unidad (arranque manual): `Quickshell.execDetached(IconTheme.relaunchCommand(pid, argv))`, donde `<pid>` es el PID leído del `Process` y `<argv>` son las líneas que siguen a `ARGV`, sin líneas vacías.
- Si no se puede leer ni la unidad ni el `argv`, escribe un aviso con `console.warn` y no hace nada más.

- [ ] **Paso 4: Declarar el tipo en el qmldir**

En `modules/icons/qmldir`, añadir la línea `IconThemeWatcher 1.0 IconThemeWatcher.qml` (tipo normal, sin la palabra `singleton`; el singleton que ya existe, `IconResolver`, no cambia).

- [ ] **Paso 5: Instanciar el vigilante en `shell.qml`**

En `shell.qml`: añadir `import "modules/icons"` junto a los demás imports, y un hijo de `shellRoot`:

```qml
    // Vigilante del tema de iconos: reinicia la shell cuando KDE cambia de
    // tema, porque el proceso lee el tema una sola vez al arrancar.
    IconThemeWatcher {
        id: iconThemeWatcher
    }
```

- [ ] **Paso 6: Ejecutar el contrato y ver que pasa**

Correr: `uv run pytest tests/test_icon_theme_watcher.py -q`

Esperado: `5 passed`.

- [ ] **Paso 7: Arrancar la shell y comprobar que no hay errores de QML**

Correr: `systemctl --user restart app-caparazon@autostart.service` y, en el log de Quickshell (`/run/user/1000/quickshell/by-id/`), comprobar que no aparece ningún `failed to load component` ni `IconThemeWatcher is not a type`.

Esperado: la shell vuelve a levantar la barra y el dock, y el log no muestra errores de QML.

- [ ] **Paso 8: Commit**

```bash
git add modules/icons/IconThemeWatcher.qml modules/icons/qmldir shell.qml tests/test_icon_theme_watcher.py
git commit -m "Shell: reinicia sola cuando cambia el tema de iconos"
```

---

### Tarea 3: Limpieza de la cadena muerta `networkIcon`

**Archivos:**
- Crear: `tests/test_resource_monitor_output.py`
- Modificar: `modules/bar/resource-monitor.sh`
- Modificar: `modules/bar/ResourceMonitorService.qml`
- Modificar: `modules/bar/Bar.qml`
- Modificar: `modules/bar/ResourceMonitor.qml`
- Modificar: `shell.qml` (quitar el paso de `networkIcon`)

**Interfaces:**
- Consume: nada.
- Produce: `modules/bar/resource-monitor.sh` entrega una línea con exactamente seis campos separados por espacio: `cpu ram gpu swap net power_profile`. `ResourceMonitorService` expone `cpu`, `ram`, `gpu`, `swap`, `network` y `powerProfile`, y ninguna propiedad `networkIcon`.

- [ ] **Paso 1: Escribir el test que falla**

Crear `tests/test_resource_monitor_output.py`:

```python
"""La línea del muestreo lleva los seis valores que la shell consume."""

import shutil
import subprocess
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY_ROOT / "modules" / "bar" / "resource-monitor.sh"


def test_the_sampler_emits_six_fields() -> None:
    """La primera línea del script tiene seis campos y ninguno es un icono."""
    bash = shutil.which("bash")
    if bash is None:
        pytest.skip("bash no disponible")
    runner = bash or "bash"
    with pytest.raises(subprocess.TimeoutExpired) as excinfo:
        _ = subprocess.run(  # noqa: S603
            [runner, str(SCRIPT)],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    stdout = excinfo.value.stdout
    assert stdout is not None
    # Al agotarse el tiempo, TimeoutExpired guarda bytes aunque se pida texto.
    first = stdout.decode().strip().splitlines()[0]
    fields = first.split()
    assert len(fields) == 6
    assert fields[5] in {"performance", "balanced", "power-saver"}
```

El script no termina nunca, así que el test lo corta con el tiempo de espera y usa la salida parcial que `subprocess.TimeoutExpired` conserva.

- [ ] **Paso 2: Ejecutar el test y ver que falla**

Correr: `uv run pytest tests/test_resource_monitor_output.py -q`

Esperado: `1 failed`, con siete campos en vez de seis.

- [ ] **Paso 3: Quitar `net_icon` del script**

En `modules/bar/resource-monitor.sh`:

- Borra el bloque que calcula `net_icon` (la asignación `net_icon=network-wired` y el `if` que la cambia a `network-wireless`).
- Deja el `printf` con seis valores: `cpu ram gpu swap net power_profile`, y el `%s` final con `$power_profile`.

Cuidado: el bloque que calcula `net_icon` está dentro del `if` que elige la interfaz; ese `if` también fija `iface` y `speed`, que se quedan como están.

- [ ] **Paso 4: Ejecutar el test y ver que pasa**

Correr: `uv run pytest tests/test_resource_monitor_output.py -q`

Esperado: `1 passed`.

- [ ] **Paso 5: Quitar la propiedad del servicio**

En `modules/bar/ResourceMonitorService.qml`: borra `property string networkIcon: "network-wired"` y la línea `root.networkIcon = fields[6] || "network-wired";`, y cambia el corte del parser de `fields.length < 7` a `fields.length < 6`.

- [ ] **Paso 6: Quitar el cableado en `shell.qml`, `Bar.qml` y `ResourceMonitor.qml`**

- `shell.qml`: borra la línea `networkIcon: resourceService.networkIcon`.
- `modules/bar/Bar.qml`: borra `property string networkIcon: "network-wired"` y la línea `networkIcon: bar.networkIcon` del `ResourceMonitor`.
- `modules/bar/ResourceMonitor.qml`: borra `property string networkIcon: "network-wired"`. El componente sigue usando `networkSource`, que va por `IconResolver.firstOf`.

- [ ] **Paso 7: Comprobar que no queda ni un rastro**

Correr: `grep -rn "networkIcon" modules/ shell.qml`

Esperado: no devuelve nada.

Correr: `grep -rn "net_icon" modules/`

Esperado: no devuelve nada.

- [ ] **Paso 8: Arrancar la shell y comprobar el monitor**

Correr: `systemctl --user restart app-caparazon@autostart.service`

Esperado: la barra muestra CPU, RAM, GPU, Swap y Red con iconos, y el log no muestra errores de QML.

- [ ] **Paso 9: Commit**

```bash
git add modules/bar/resource-monitor.sh modules/bar/ResourceMonitorService.qml \
    modules/bar/Bar.qml modules/bar/ResourceMonitor.qml shell.qml \
    tests/test_resource_monitor_output.py
git commit -m "Barra: fuera la propiedad networkIcon sin uso"
```

---

### Tarea 4: Comprobación en vivo, documentación y entrega

**Archivos:**
- Modificar: `README.md`

**Interfaces:**
- Consume: todo lo anterior.
- Produce: el README documenta el reinicio automático, y la rama llega a `main`.

- [ ] **Paso 1: Preparar la comprobación en vivo del camino de systemd**

Copia de seguridad: `cp ~/.config/kdeglobals /tmp/opencode/kdeglobals.bak`

Anota el estado actual de la unidad: `systemctl --user show app-caparazon@autostart.service -p ActiveEnterTimestamp -p MainPID`

Captura de referencia: `spectacle -b -n -o /tmp/opencode/antes.png`

- [ ] **Paso 2: Cambiar el tema de iconos como lo hace KConfig**

```bash
sed 's/^Theme=.*/Theme=breeze/' ~/.config/kdeglobals > /tmp/opencode/kdeglobals.nuevo
mv /tmp/opencode/kdeglobals.nuevo ~/.config/kdeglobals
```

El `mv` es la sustitución atómica que hace KConfig: con ella se comprueba también que el `FileSystemWatcher` sobre el directorio sigue detectando los cambios.

- [ ] **Paso 3: Comprobar que la shell se reinició sola**

Correr: `systemctl --user show app-caparazon@autostart.service -p ActiveEnterTimestamp -p MainPID`

Esperado: `ActiveEnterTimestamp` es posterior al momento del cambio y el `MainPID` es distinto del anterior. Ésta es la prueba de que el vigilante detectó el cambio y reinició el proceso.

- [ ] **Paso 4: Comprobar que los iconos son los del tema nuevo**

Correr: `spectacle -b -n -o /tmp/opencode/despues.png`

Esperado: los iconos de la barra y del dock son los del tema `breeze`, distintos de los de la captura de referencia.

- [ ] **Paso 5: Restaurar el tema original**

```bash
cp /tmp/opencode/kdeglobals.bak ~/.config/kdeglobals
```

Esperado: la shell vuelve a reiniciarse sola y recupera los iconos de `Tela-dark`. Confirma que el ciclo no se queda en un único reinicio.

- [ ] **Paso 6: Comprobar el camino sin systemd con una sonda aislada**

La sonda usa el vigilante real, pero con un `HOME` falso y fuera de systemd, así no toca la sesión:

```bash
mkdir -p /tmp/opencode/sonda/modules /tmp/opencode/sonda/home/.config
cp -r modules/icons /tmp/opencode/sonda/modules/
printf '[Icons]\nTheme=Tela-dark\n' > /tmp/opencode/sonda/home/.config/kdeglobals
```

La sonda (`/tmp/opencode/sonda/shell.qml`) es un `ShellRoot` que importa `"./modules/icons"`, instancia un `IconThemeWatcher` y, en `Component.onCompleted`, escribe una línea con la hora en `/tmp/opencode/sonda/inicios.log`.

Correr la sonda en primer plano, sin systemd, y cambiar el tema del `HOME` falso:

```bash
HOME=/tmp/opencode/sonda/home XDG_CONFIG_HOME=/tmp/opencode/sonda/home/.config \
    XDG_DATA_DIRS=/home/ezku/.local/share:/usr/local/share:/usr/share \
    quickshell -p /tmp/opencode/sonda > /tmp/opencode/sonda/sonda.log 2>&1 &
sleep 3
printf '[Icons]\nTheme=breeze\n' > /tmp/opencode/sonda/home/.config/kdeglobals
sleep 3
```

Esperado: `/tmp/opencode/sonda/inicios.log` tiene **dos** líneas: la sonda arrancó, detectó el cambio y se relanzó sola con su mismo `argv`. La segunda línea debe llegar unos segundos después de la primera.

Limpiar al terminar: `pkill -f "quickshell -p /tmp/opencode/sonda"`.

- [ ] **Paso 7: Documentar en el README**

En `README.md`, dentro de la sección "Integración con KDE", añadir un párrafo: al cambiar el tema de iconos, Caparazón reinicia la shell sola, porque el proceso lee el tema una sola vez al arrancar; el reinicio dura un segundo y vacía el historial del portapapeles.

- [ ] **Paso 8: Puerta de calidad**

Correr: `uv run pytest -q`, `uv run ruff check .`, `uv run basedpyright`

Esperado: los tres sin fallos ni avisos nuevos.

- [ ] **Paso 9: Commit**

```bash
git add README.md
git commit -m "Documenta el reinicio automatico al cambiar el tema de iconos"
```

- [ ] **Paso 10: Mergear y subir**

```bash
git checkout main
git merge --no-ff feature/vigilante-tema-iconos -m "Merge de la rama 'feature/vigilante-tema-iconos'"
git push origin main
```

Esperado: `main` queda en `origin/main` y el árbol limpio.

# Perfil energético en niri — `caparazon-wm power-profile` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el chip de perfil energético de Caparazon funcione en Plasma y en niri, con un único punto de contacto (`caparazon-wm power-profile`) que hable con Solid en KDE y con `power-profiles-daemon` fuera de KDE.

**Architecture:** El CLI `caparazon-wm.py` gana un subcomando `power-profile` (consulta y `--set`) con dos proveedores tras un `Protocol`: `SolidPowerProfile` (D-Bus de sesión, `qdbus6`) y `PpdPowerProfile` (`powerprofilesctl`). El compositor elige el orden de preferencia (kwin → solid, resto → ppd) y, si el preferido no está disponible, se prueba el otro; sin ninguno, el backend es `none`. El QML `PowerProfile.qml` deja de hablar con `qdbus6`: lee el JSON con `Process`/`StdioCollector` y aplica perfiles con `--set`, ciclando sólo por los perfiles que el backend declara.

**Tech Stack:** Python 3.11+ (`subprocess`, `json`, `StrEnum`, dataclasses), Quickshell/QML (`Quickshell.Io.Process`, `StdioCollector`), pytest con binarios falsos en `PATH`, `qdbus6`, `powerprofilesctl`.

**Spec:** `docs/superpowers/specs/2026-11-21-power-profile-niri-design.md`

## Global Constraints

- Idioma del código, comentarios y docs: español.
- TDD estricto: test rojo antes de cada cambio de comportamiento; nada de commits durante la ejecución (el commit se pide explícitamente).
- El QML no habla con D-Bus de KDE: todo pasa por `caparazon-wm`.
- Vocabulario único de perfiles: `power-saver`, `balanced`, `performance` (idéntico en Solid y en power-profiles-daemon, verificado en vivo).
- `install.sh` no instala `power-profiles-daemon`: sólo lo detecta y avisa.
- Ruff mantiene `include = ["tests/**/*.py", "modules/secondmenu/gcal.py"]`: no se amplía al CLI.
- Código nuevo del CLI en estilo estricto (tipos explícitos, `Protocol` para el proveedor, dataclasses congelados, `match` para variantes, sin `Any`/`object`/`cast`).

## Review Focus

1. **Equipo sin `powerprofilesctl`** (este equipo no lo tiene) — la consulta debe responder con código 0 y `backend: "none"`, y `--set` con código 1 y mensaje, sin traceback. → test: PATH sin ninguno de los dos binarios → consulta JSON con `none`; `--set` devuelve 1.
2. **PPD sin perfil `performance`** (depende del hardware) — el chip debe ciclar sólo por los perfiles que el backend declara, no por una lista fija. → test: PPD falso que declara sólo `power-saver` y `balanced` → `choices` sale con esos dos.
3. **Formatos distintos del mismo dato** — Solid por `qdbus6` devuelve un perfil por línea y `powerprofilesctl list` devuelve bloques con sangría; un parser que asuma un solo formato rompe el otro backend. → test: PPD falso con salida estilo bloques → `choices` correctas.
4. **Arranque en frío** — el chip no debe quedarse mostrando `balanced` fingido si el backend no responde o no existe. → test de contrato QML: el perfil inicial viene del CLI, no de una constante.
5. **Perfil inválido** (`--set turbo`) — debe fallar con código 1 y mensaje claro, sin aplicar nada. → test: `--set turbo` → código 1 y stderr con el nombre del perfil y los disponibles.

---

### Task 1: CLI `power-profile` con backend power-profiles-daemon

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_caparazon_wm.py`

**Interfaces:**
- Produces: `caparazon-wm power-profile` → stdout JSON `{"profile": str|None, "choices": [str], "backend": "solid"|"ppd"|"none"}`; `caparazon-wm power-profile --set <perfil>` → código 0 al aplicar, 1 con mensaje en stderr si no hay backend o el perfil no existe.
- Produces (código): `PowerProfileBackend(StrEnum)` con `SOLID="solid"`, `PPD="ppd"`, `NONE="none"`; `PowerProfileState` (dataclass frozen+slots) con `profile: str | None`, `choices: tuple[str, ...]`, `backend: PowerProfileBackend`; `PowerProfileProvider(Protocol)` con `backend: PowerProfileBackend`, `available() -> bool`, `read() -> tuple[str | None, tuple[str, ...]]`, `apply(profile: str) -> bool`; `PpdPowerProfile` con esos cuatro miembros.

- [ ] **Step 1: Test en rojo** — en `tests/test_caparazon_wm.py`, con el patrón de `_run_cli(..., fake_bin=...)` ya existente:
  - `test_power_profile_reads_ppd`: fake `powerprofilesctl` que responde a `list` con bloques `power-saver:\n    Description: …\nbalanced:\n    Description: …\n` y a `get` con `balanced` → JSON con `backend == "ppd"`, `profile == "balanced"`, `choices == ("power-saver", "balanced")`.
  - `test_power_profile_sets_ppd`: fake `powerprofilesctl` que escribe la llamada a un fichero → `--set power-saver` devuelve 0 y el fichero registra `set power-saver`.
  - `test_power_profile_rejects_unknown_profile`: `--set turbo` → código 1, stderr con `turbo` y `power-saver`.
  - `test_power_profile_without_backend`: PATH sin `powerprofilesctl` ni `qdbus6` → consulta devuelve 0 con `backend == "none"` y `profile is None`; `--set balanced` devuelve 1 con mensaje.
- [ ] **Step 2: Ejecutar y ver que falla** — `uv run pytest tests/test_caparazon_wm.py -k power_profile -v` → FAIL (subcomando inexistente → "comando desconocido", código 2).
- [ ] **Step 3: Implementar** en `integration/bin/caparazon-wm.py`:
  - `PpdPowerProfile.available()`: `shutil.which("powerprofilesctl") is not None`.
  - `PpdPowerProfile.read()`: `powerprofilesctl list` → líneas sin sangría que acaban en `:` son nombres de perfil; `powerprofilesctl get` → perfil activo. `read()` devuelve `(perfil, choices)`; si `list` falla → `("", ())`.
  - `PpdPowerProfile.apply(profile)`: `powerprofilesctl set <perfil>` → `True` si returncode 0.
  - `power_profile_state()` y `power_profile_apply(profile) -> int` más el enganche en `main()`: `power-profile` sin args imprime el JSON; `power-profile --set <perfil>` aplica; `--set` con otro valor → código 2 con uso.
  - En esta task el backend por compositor todavía no entra: `power_profile_provider()` devuelve sólo el proveedor PPD y `Solid` aún no existe (lo añade la Task 2). El JSON ya sale con la clave `backend` para no cambiar el contrato después.
- [ ] **Step 4: Verificar en verde** — `uv run pytest tests/test_caparazon_wm.py -k power_profile -v` → PASS; `uv run pytest -q` → sin regresiones.
- [ ] **Step 5: Registrar** el avance en `.superpowers/sdd/2026-11-21-compositor-portatil/progress.md` (sin commit).

### Task 2: Backend Solid y selección por compositor

**Files:**
- Modify: `integration/bin/caparazon-wm.py`
- Test: `tests/test_caparazon_wm.py`

**Interfaces:**
- Consumes: `PowerProfileProvider`, `PowerProfileBackend`, `PpdPowerProfile` de la Task 1.
- Produces: `SolidPowerProfile` con `backend == PowerProfileBackend.SOLID`; `power_profile_provider(compositor: str) -> PowerProfileProvider | None` que ordena Solid→PPD para `kwin` y PPD→Solid para cualquier otro, y devuelve `None` si ninguno está disponible.

- [ ] **Step 1: Test en rojo** — en `tests/test_caparazon_wm.py`:
  - `test_power_profile_reads_solid`: fake `qdbus6` que responde `profileChoices` con una línea por perfil (`power-saver\nbalanced\nperformance\n`) y `currentProfile` con `performance` → JSON con `backend == "solid"`, `profile == "performance"`, `choices` con los tres.
  - `test_power_profile_sets_solid`: fake `qdbus6` que registra la llamada → `--set performance` devuelve 0 y el fichero registra `setProfile performance`.
  - `test_power_profile_prefers_solid_on_kwin`: con ambos backends falsos disponibles y `NIRI_SOCKET` sin setear y `busctl` respondiendo → `backend == "solid"`.
  - `test_power_profile_prefers_ppd_on_niri`: con `NIRI_SOCKET` seteado → `backend == "ppd"`.
- [ ] **Step 2: Ejecutar y ver que falla** — `uv run pytest tests/test_caparazon_wm.py -k power_profile -v` → FAIL (backend Solid ausente).
- [ ] **Step 3: Implementar** en `integration/bin/caparazon-wm.py`:
  - `SolidPowerProfile.available()`: `shutil.which("qdbus6") is not None`.
  - `SolidPowerProfile.read()`: `qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement/Actions/PowerProfile org.kde.Solid.PowerManagement.Actions.PowerProfile.profileChoices` → líneas no vacías como nombres; `.currentProfile` → perfil activo.
  - `SolidPowerProfile.apply(profile)`: la misma llamada D-Bus con `.setProfile <perfil>` → `True` si returncode 0.
  - `power_profile_provider(compositor)`: orden de preferencia por compositor con tabla `{"kwin": (SOLID, PPD), "niri": (PPD, SOLID)}` y PPD primero para cualquier compositor desconocido; devuelve el primero `available()`.
  - `power_profile_state()` usa el proveedor elegido; si no hay ninguno → `PowerProfileState(profile=None, choices=(), backend=NONE)`.
  - `power_profile_apply(profile)`: sin proveedor → stderr `power-profile: no hay backend de perfil energético disponible` y código 1; con proveedor → valida el perfil contra `read()[1]` (lista vacía = error de lectura, código 1) y aplica.
- [ ] **Step 4: Verificar en verde** — `uv run pytest tests/test_caparazon_wm.py -k power_profile -v` → PASS; `uv run pytest -q` → sin regresiones.
- [ ] **Step 5: Comprobar contra el sistema real** — `python3 integration/bin/caparazon-wm.py power-profile` en esta sesión Plasma → JSON con `backend "solid"` y `profile` igual al de `qdbus6 ... currentProfile`.
- [ ] **Step 6: Registrar** el avance en el ledger (sin commit).

### Task 3: `PowerProfile.qml` habla con el CLI

**Files:**
- Modify: `modules/bar/PowerProfile.qml`
- Test: `tests/test_shell_qml_cli.py`

**Interfaces:**
- Consumes: `caparazon-wm power-profile` (JSON `profile`, `choices`, `backend`) y `caparazon-wm power-profile --set <perfil>` de las Tasks 1–2.
- Produces: el chip refleja el perfil real, cicla por las `choices` del backend y se atenúa sin backend.

- [ ] **Step 1: Test en rojo** — en `tests/test_shell_qml_cli.py`:
  - `test_power_profile_uses_cli`: el fichero contiene `"caparazon-wm"` y `"power-profile"`; no contiene `qdbus6` ni `org.kde`.
  - `test_power_profile_has_no_hardcoded_initial_profile`: el fichero no contiene `property string profile: "balanced"` (el perfil inicial sale del CLI).
- [ ] **Step 2: Ejecutar y ver que falla** — `uv run pytest tests/test_shell_qml_cli.py -v` → FAIL.
- [ ] **Step 3: Implementar** en `modules/bar/PowerProfile.qml`:
  - `Process { id: query; command: ["caparazon-wm", "power-profile"]; stdout: StdioCollector { onStreamFinished: … } }` que al terminar parsea el JSON y fija `profile`, `choices` y `backend` (patrón de `ActiveWindowService.qml`).
  - `property var choices: []` y `property string backend: ""`; `property string profile: ""` (sin valor inventado) y `displayProfile` refleja `profile` cuando llega.
  - `applyProfile(next)`: llama `caparazon-wm power-profile --set <next>` con `Quickshell.execDetached` y programa una re-lectura (Timer de 250 ms) para que el estado real sea el que se muestra (si el comando falló, el chip vuelve al perfil anterior).
  - `cycle(step)`: cicla sobre `choices` del backend; si `choices` está vacío no hace nada.
  - Sin backend (`backend === "none"` o `choices` vacío): el chip se atenúa (opacidad baja), el `MouseArea` no reacciona y el tooltip dice que no hay soporte.
  - El resto (tono, colores, iconos) se conserva; `BarIcons.powerProfileNames` ya cubre los tres nombres.
- [ ] **Step 4: Verificar en verde** — `uv run pytest tests/test_shell_qml_cli.py -v` → PASS; `uv run pytest -q` → sin regresiones.
- [ ] **Step 5: Comprobar en vivo** — recargar la shell en Plasma y verificar que el chip muestra el perfil real (`performance`) y que la rueda lo cambia; `python3 integration/bin/caparazon-wm.py power-profile` refleja el cambio.
- [ ] **Step 6: Registrar** el avance en el ledger (sin commit).

### Task 4: Documentación y verificación final

**Files:**
- Modify: `README.md`
- Modify: `install.sh`
- Modify: `tests/test_install_compositor_agnostic.py`
- Modify: `.superpowers/sdd/2026-11-21-compositor-portatil/progress.md`

- [ ] **Step 1: Test en rojo** — en `tests/test_install_compositor_agnostic.py`:
  - `test_the_installer_warns_when_niri_has_no_power_profiles_daemon`: instalación en sesión niri sin `powerprofilesctl` en el PATH → salida con `power-profiles-daemon` y código 0 (avisa, no instala ni falla).
- [ ] **Step 2: Ejecutar y ver que falla** — `uv run pytest tests/test_install_compositor_agnostic.py -k power_profiles -v` → FAIL.
- [ ] **Step 3: Implementar** en `install.sh`: en la rama no-KDE de la instalación del tema, si `powerprofilesctl` no está en el PATH, avisar de que el selector de perfil energético no funcionará en niri y de que se instala con `sudo apt install power-profiles-daemon` (sin instalarlo).
- [ ] **Step 4: Verificar en verde** — `uv run pytest tests/test_install_compositor_agnostic.py -v` → PASS.
- [ ] **Step 5: Documentar** en `README.md`: sección "Perfil energético" con la tabla de perfiles, cómo se comporta en Plasma (Solid) y en niri (`power-profiles-daemon`), el paso manual `sudo apt install power-profiles-daemon` sólo para sesiones niri y el aviso de no instalarlo si se usa Plasma a diario (pelea con powerdevil por el governor).
- [ ] **Step 6: Verificar** — `uv run pytest -q` → todo en verde; `uv run ruff check` → los mismos 29 errores preexistentes y ninguno nuevo; `bash -n install.sh` → OK; `shellcheck install.sh` → OK; `niri validate -c integration/niri/config.kdl` → OK.
- [ ] **Step 7: Registrar** el cierre en el ledger (sin commit; el commit lo pide el usuario).

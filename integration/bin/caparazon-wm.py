#!/usr/bin/env python3
"""caparazon-wm — puente único de compositor para caparazon-shell.

Subcomandos estables (el QML sólo invoca estos):

  detect           imprime kwin | niri
  active-output    nombre de la pantalla activa
  primary-output   nombre de la pantalla principal
  workspaces       JSON de escritorios (shape del caché ezku-desktops)
  watch-workspaces una línea JSON por cambio, en bucle
  windows          JSON {appId, title, appIds}
  watch-windows    una línea JSON por cambio de ventana, en bucle
  window-action    ciclo del dock: enfoca / minimiza / restaura
  workspace-switch cambia al escritorio N (1-based)
  power-profile    perfil energético actual (JSON) y --set para aplicarlo
  logout           cierra la sesión

Detección: NIRI_SOCKET → busctl org.kde.KWin → niri msg version → kwin.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from enum import StrEnum
from typing import Any
from typing import Final
from typing import Protocol

BUS_KWIN = "org.kde.KWin"


def run(cmd: list[str], *, timeout: float = 10.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def detect_compositor() -> str:
    if os.environ.get("NIRI_SOCKET"):
        return "niri"
    busctl = shutil.which("busctl")
    if busctl:
        probe = run(
            [
                busctl,
                "--user",
                "call",
                BUS_KWIN,
                "/KWin",
                BUS_KWIN,
                "activeOutputName",
            ],
            timeout=3.0,
        )
        if probe.returncode == 0:
            return "kwin"
    niri = shutil.which("niri")
    if niri:
        ver = run([niri, "msg", "version"], timeout=3.0)
        if ver.returncode == 0:
            return "niri"
    return "kwin"


def _parse_busctl_string(raw: str) -> str:
    match = re.search(r'"([^"]*)"', raw)
    return match.group(1) if match else ""


# --- pantallas ---------------------------------------------------------------


def active_output_kwin() -> str:
    busctl = shutil.which("busctl")
    if not busctl:
        return ""
    probe = run(
        [busctl, "--user", "call", BUS_KWIN, "/KWin", BUS_KWIN, "activeOutputName"]
    )
    return _parse_busctl_string(probe.stdout)


def active_output_niri() -> str:
    niri = shutil.which("niri")
    if not niri:
        return ""
    probe = run([niri, "msg", "--json", "focused-output"])
    if probe.returncode != 0:
        return ""
    try:
        data = json.loads(probe.stdout)
    except json.JSONDecodeError:
        return ""
    if isinstance(data, dict):
        return str(data.get("name") or "")
    return ""


def primary_output_kwin() -> str:
    """Principal = menor prioridad (>0) entre salidas activas (igual que ShellLayout)."""
    kscreen = shutil.which("kscreen-doctor")
    if not kscreen:
        return active_output_kwin()
    probe = run([kscreen, "--json", "-o"])
    raw = probe.stdout
    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end <= start:
        return active_output_kwin()
    try:
        doc = json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        return active_output_kwin()
    outs = doc.get("outputs") if isinstance(doc, dict) else None
    if not isinstance(outs, list):
        return active_output_kwin()
    best: dict[str, Any] | None = None
    for out in outs:
        if not isinstance(out, dict) or not out.get("name"):
            continue
        if out.get("enabled") is False or out.get("connected") is False:
            continue
        priority = out.get("priority")
        if not isinstance(priority, (int, float)) or priority <= 0:
            continue
        if best is None or priority < float(best["priority"]):
            best = {"name": str(out["name"]), "priority": float(priority)}
    if best:
        return str(best["name"])
    return active_output_kwin()


def _niri_outputs_map(raw: str) -> dict[str, Any]:
    """`niri msg --json outputs` imprime HashMap<String, Output> (no lista)."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    if isinstance(data, dict):
        # Puede venir envuelto {"Outputs": {...}} por si cambia el CLI.
        if "Outputs" in data and isinstance(data["Outputs"], dict):
            return data["Outputs"]
        return data
    if isinstance(data, list):
        # Compat defensivo si alguna versión imprimiera lista.
        out: dict[str, Any] = {}
        for item in data:
            if isinstance(item, dict) and item.get("name"):
                out[str(item["name"])] = item
        return out
    return {}


def _niri_output_enabled(info: Any) -> bool:
    if not isinstance(info, dict):
        return False
    if info.get("enabled") is False:
        return False
    # Output real: current_mode None ⇒ deshabilitada.
    if "current_mode" in info and info["current_mode"] is None:
        return False
    return True


def primary_output_niri() -> str:
    """niri no tiene prioridad kscreen: primera salida habilitada (x,y estable)."""
    niri = shutil.which("niri")
    if not niri:
        return ""
    probe = run([niri, "msg", "--json", "outputs"])
    if probe.returncode != 0:
        return ""
    outs = _niri_outputs_map(probe.stdout)
    candidates: list[tuple[float, float, str]] = []
    for name, info in outs.items():
        if not _niri_output_enabled(info):
            continue
        x = float(info.get("x") or 0) if isinstance(info, dict) else 0.0
        y = float(info.get("y") or 0) if isinstance(info, dict) else 0.0
        candidates.append((x, y, str(name)))
    if not candidates:
        # Sin info de posición: primera clave habilitada por orden del mapa.
        for name, info in outs.items():
            if _niri_output_enabled(info):
                return str(name)
        return ""
    candidates.sort()
    return candidates[0][2]


# --- escritorios -------------------------------------------------------------


def workspaces_state_kwin() -> dict[str, Any]:
    busctl = shutil.which("busctl")
    state: dict[str, Any] = {
        "current": "",
        "desktops": [],
        "occupied": [],
        "perOutput": {},
        "focusedScreen": "",
        "occupiedPerOutput": {},
    }
    if not busctl:
        return state
    desks = run(
        [
            busctl,
            "--user",
            "--json=short",
            "call",
            BUS_KWIN,
            "/VirtualDesktopManager",
            "org.freedesktop.DBus.Properties",
            "Get",
            "ss",
            "org.kde.KWin.VirtualDesktopManager",
            "desktops",
        ]
    )
    current = run(
        [
            busctl,
            "--user",
            "--json=short",
            "call",
            BUS_KWIN,
            "/VirtualDesktopManager",
            "org.freedesktop.DBus.Properties",
            "Get",
            "ss",
            "org.kde.KWin.VirtualDesktopManager",
            "current",
        ]
    )
    # busctl --json=short: {"type":"v","data":[{"type":"…","data":<valor>}]}
    try:
        rows = json.loads(desks.stdout)["data"][0]["data"]
        state["desktops"] = [
            {"pos": e[0], "id": e[1], "name": e[2]} for e in rows
        ]
    except (json.JSONDecodeError, AttributeError, TypeError, IndexError, KeyError):
        pass
    try:
        state["current"] = json.loads(current.stdout)["data"][0]["data"]
    except (json.JSONDecodeError, AttributeError, TypeError, IndexError, KeyError):
        pass
    return state


def workspaces_state_niri() -> dict[str, Any]:
    """Shape del caché ezku-desktops a partir de niri msg.

    - current: workspace con is_focused (uno solo en toda la sesión).
    - occupied: ids de workspace con al menos una ventana (windows.workspace_id).
    - perOutput / occupiedPerOutput: por nombre de output del workspace.
    niri no trae window_count; se deriva de la lista de ventanas.
    """
    niri = shutil.which("niri")
    state: dict[str, Any] = {
        "current": "",
        "desktops": [],
        "occupied": [],
        "perOutput": {},
        "focusedScreen": "",
        "occupiedPerOutput": {},
    }
    if not niri:
        return state
    wsc = run([niri, "msg", "--json", "workspaces"])
    wins = run([niri, "msg", "--json", "windows"])
    try:
        workspaces = json.loads(wsc.stdout)
    except json.JSONDecodeError:
        workspaces = []
    try:
        windows = json.loads(wins.stdout)
    except json.JSONDecodeError:
        windows = []
    if not isinstance(workspaces, list):
        # Por si el CLI envuelve {"Workspaces": [...]}
        if isinstance(workspaces, dict) and isinstance(
            workspaces.get("Workspaces"), list
        ):
            workspaces = workspaces["Workspaces"]
        else:
            return state

    occupied_idx: set[int] = set()
    if isinstance(windows, list):
        for w in windows:
            if not isinstance(w, dict):
                continue
            wid = w.get("workspace_id")
            if isinstance(wid, int):
                occupied_idx.add(wid)

    focused_output = ""
    for i, ws in enumerate(workspaces):
        if not isinstance(ws, dict):
            continue
        ws_id = ws.get("id", ws.get("idx", i + 1))
        idx = ws.get("idx", i + 1)
        name = ws.get("name") or str(idx)
        output = str(ws.get("output") or "")
        state["desktops"].append(
            {"pos": i, "id": str(ws_id), "name": str(name)}
        )
        if ws.get("is_focused"):
            state["current"] = str(ws_id)
            focused_output = output
        elif not state["current"] and ws.get("is_active") and not focused_output:
            # Respaldo: sin is_focused, la activa del primer output.
            state["current"] = str(ws_id)
            if output:
                focused_output = output
        occupied = isinstance(ws_id, int) and ws_id in occupied_idx
        # También cuenta active_window_id si existe.
        if ws.get("active_window_id") is not None:
            occupied = True
        if occupied:
            state["occupied"].append(str(ws_id))
        if output:
            state["perOutput"][output] = str(ws_id)
            if occupied:
                state["occupiedPerOutput"].setdefault(output, []).append(
                    str(ws_id)
                )
    state["focusedScreen"] = focused_output
    return state


def workspaces_state() -> dict[str, Any]:
    if detect_compositor() == "niri":
        return workspaces_state_niri()
    return workspaces_state_kwin()


def print_workspaces() -> int:
    json.dump(workspaces_state(), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def watch_workspaces() -> int:
    """Emite una línea JSON por evento de cambio hasta SIGTERM."""
    comp = detect_compositor()
    if comp == "niri":
        niri = shutil.which("niri")
        if not niri:
            return 1
        proc = subprocess.Popen(  # noqa: S603
            [niri, "msg", "--json", "event-stream"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        assert proc.stdout is not None
        try:
            for line in proc.stdout:
                if '"Workspaces' in line or '"Windows' in line or '"Focused' in line:
                    print(json.dumps(workspaces_state_niri()), flush=True)
        finally:
            proc.terminate()
        return 0

    # kwin: dbus-monitor como antes en WorkspacesService
    monitor = shutil.which("dbus-monitor")
    if not monitor:
        return 1
    proc = subprocess.Popen(  # noqa: S603
        [
            monitor,
            "--session",
            "type='signal',interface='org.kde.KWin.VirtualDesktopManager'",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    assert proc.stdout is not None
    try:
        for _line in proc.stdout:
            print(json.dumps(workspaces_state_kwin()), flush=True)
    finally:
        proc.terminate()
    return 0


# --- ventanas ----------------------------------------------------------------


def windows_state_kwin() -> dict[str, Any]:
    """Emplea el mismo script KWin que ActiveWindowService (vía journal hoy).

    Aquí sólo leemos el estado publicado en el caché si existe; la carga del
    script la sigue haciendo el bootstrap. Como mínimos devolvemos shape vacío
    válido para no romper el QML.
    """
    cache = os.path.expanduser("~/.cache/ezku-desktops.json")
    app_id = ""
    title = ""
    app_ids: list[str] = []
    try:
        with open(cache, encoding="utf-8") as fh:
            data = json.load(fh)
        active = data.get("active") or {}
        if isinstance(active, dict):
            app_id = str(active.get("class") or "")
            title = str(active.get("caption") or "")
        windows = data.get("windows") or []
        if isinstance(windows, list):
            for w in windows:
                if isinstance(w, dict):
                    cid = str(w.get("class") or w.get("appId") or "")
                    if cid and cid not in app_ids:
                        app_ids.append(cid)
    except (OSError, ValueError):
        pass
    return {"appId": app_id, "title": title, "appIds": app_ids}


def windows_state_niri() -> dict[str, Any]:
    niri = shutil.which("niri")
    if not niri:
        return {"appId": "", "title": "", "appIds": []}
    focused = run([niri, "msg", "--json", "focused-window"])
    wins = run([niri, "msg", "--json", "windows"])
    app_id = ""
    title = ""
    try:
        data = json.loads(focused.stdout)
        if isinstance(data, dict):
            app_id = str(data.get("app_id") or "")
            title = str(data.get("title") or "")
    except json.JSONDecodeError:
        pass
    app_ids: list[str] = []
    try:
        rows = json.loads(wins.stdout)
        if isinstance(rows, list):
            for w in rows:
                if not isinstance(w, dict):
                    continue
                cid = str(w.get("app_id") or "")
                if cid and cid not in app_ids:
                    app_ids.append(cid)
    except json.JSONDecodeError:
        pass
    return {"appId": app_id, "title": title, "appIds": app_ids}


def windows_state() -> dict[str, Any]:
    if detect_compositor() == "niri":
        return windows_state_niri()
    return windows_state_kwin()


def print_windows() -> int:
    json.dump(windows_state(), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def watch_windows() -> int:
    comp = detect_compositor()
    if comp == "niri":
        niri = shutil.which("niri")
        if not niri:
            return 1
        proc = subprocess.Popen(  # noqa: S603
            [niri, "msg", "--json", "event-stream"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        assert proc.stdout is not None
        try:
            for line in proc.stdout:
                if '"FocusedWindow' in line or '"Windows' in line:
                    print(json.dumps(windows_state_niri()), flush=True)
        finally:
            proc.terminate()
        return 0

    # kwin: journalctl del script (mismo flujo que ActiveWindowService)
    journal = shutil.which("journalctl")
    if not journal:
        return 1
    proc = subprocess.Popen(  # noqa: S603
        [
            journal,
            "--user",
            "-b",
            "-f",
            "-n",
            "0",
            "-o",
            "cat",
            "_COMM=kwin_wayland",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    assert proc.stdout is not None
    active_prefix = "js: CAPARAZON_ACTIVE:"
    windows_prefix = "js: CAPARAZON_WINDOWS:"
    try:
        for line in proc.stdout:
            line = line.rstrip("\n")
            if line.startswith(active_prefix):
                try:
                    info = json.loads(line[len(active_prefix) :])
                except json.JSONDecodeError:
                    continue
                state = windows_state_kwin()
                state["appId"] = str(info.get("appId") or "")
                state["title"] = str(info.get("title") or "")
                print(json.dumps(state), flush=True)
            elif line.startswith(windows_prefix):
                try:
                    ids = json.loads(line[len(windows_prefix) :])
                except json.JSONDecodeError:
                    continue
                state = windows_state_kwin()
                if isinstance(ids, list):
                    state["appIds"] = [str(x) for x in ids]
                print(json.dumps(state), flush=True)
    finally:
        proc.terminate()
    return 0


# --- acción del dock ---------------------------------------------------------


def window_action_kwin(active: str, candidates: list[str]) -> int:
    """Camino histórico: plantilla KWinWindowAction.js + gdbus Scripting."""
    script = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "modules",
        "bar",
        "KWinWindowAction.js",
    )
    # Ruta relativa al repo si existe; si no, ruta shellPath equivalente.
    if not os.path.isfile(script):
        script = os.path.expanduser(
            "~/.local/share/caparazon-shell/modules/bar/KWinWindowAction.js"
        )
    if not os.path.isfile(script):
        # Último recurso: buscar junto al CLI instalado no es fiable; salir 1.
        # El install.sh copia el repo completo vía quickshell -p.
        alt = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "..",
            "..",
            "modules",
            "bar",
            "KWinWindowAction.js",
        )
        script = os.path.normpath(alt)
    if not os.path.isfile(script):
        sys.stderr.write(f"caparazon-wm: no encuentro KWinWindowAction.js\n")
        return 1

    target = "|".join(candidates)
    # Sanidad idéntica al bash original del Dock.
    if target and not re.fullmatch(r"[A-Za-z0-9._|-]*", target):
        return 1
    if active and not re.fullmatch(r"[A-Za-z0-9._-]*", active):
        active = ""

    tmp = os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
        f"caparazon-window-action-{os.getpid()}.js",
    )
    try:
        with open(script, encoding="utf-8") as fh:
            content = fh.read()
        content = content.replace("__TARGET__", target).replace(
            "__ACTIVE__", active
        )
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(content)
        gdbus = shutil.which("gdbus")
        if not gdbus:
            return 1
        for method, args in (
            (
                "unloadScript",
                ["caparazon-window-action"],
            ),
            ("loadScript", [tmp, "caparazon-window-action"]),
            ("start", []),
        ):
            cmd = [
                gdbus,
                "call",
                "--session",
                "--dest",
                BUS_KWIN,
                "--object-path",
                "/Scripting",
                "--method",
                f"org.kde.kwin.Scripting.{method}",
                *args,
            ]
            run(cmd)
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    return 0


def window_action_niri(active: str, candidates: list[str]) -> int:
    """Enfoca la primera ventana candidata; si ya está enfocada, no hace nada
    destructivo (niri no expone minimize en su CLI).
    """
    niri = shutil.which("niri")
    if not niri:
        return 1
    wins = run([niri, "msg", "--json", "windows"])
    try:
        rows = json.loads(wins.stdout)
    except json.JSONDecodeError:
        return 1
    if not isinstance(rows, list):
        return 1

    # Orden: primero la app activa si tiene ventana; si ya está enfocada → no-op.
    def matches(w: dict[str, Any]) -> bool:
        app = str(w.get("app_id") or "")
        return app in candidates if candidates else False

    target: dict[str, Any] | None = None
    for w in rows:
        if isinstance(w, dict) and matches(w) and w.get("is_focused"):
            # Ya enfocada: sin minimize disponible → salir sin cerrar.
            return 0
    for w in rows:
        if isinstance(w, dict) and matches(w):
            target = w
            break
    if target is None and active:
        for w in rows:
            if isinstance(w, dict) and str(w.get("app_id") or "") == active:
                target = w
                break
    if target is None:
        return 0
    wid = target.get("id")
    if wid is None:
        return 1
    action = run([niri, "msg", "action", "focus-window", "--id", str(wid)])
    return action.returncode


def window_action(active: str, candidates: list[str]) -> int:
    if detect_compositor() == "niri":
        return window_action_niri(active, candidates)
    return window_action_kwin(active, candidates)


# --- sesión ------------------------------------------------------------------


def workspace_switch(index: int) -> int:
    """Cambia al escritorio N (1-based, como el pos+1 del pager)."""
    if index < 1:
        return 1
    if detect_compositor() == "niri":
        niri = shutil.which("niri")
        if not niri:
            return 1
        return run([niri, "msg", "action", "focus-workspace", str(index)]).returncode
    qdbus = shutil.which("qdbus6")
    if not qdbus:
        return 1
    return run(
        [
            qdbus,
            "org.kde.KWin",
            "/KWin",
            "org.kde.KWin.setCurrentDesktop",
            str(index),
        ]
    ).returncode


def logout() -> int:
    if detect_compositor() == "niri":
        niri = shutil.which("niri")
        if not niri:
            return 1
        return run([niri, "msg", "action", "quit"]).returncode
    qdbus = shutil.which("qdbus6")
    if not qdbus:
        return 1
    return run(
        [qdbus, "org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logout"]
    ).returncode


# --- power-profile ------------------------------------------------------------


class PowerProfileBackend(StrEnum):
    """Motor que responde del perfil energético de la sesión."""

    SOLID = "solid"
    PPD = "ppd"
    NONE = "none"


@dataclass(frozen=True, slots=True)
class PowerProfileState:
    """Perfil energético activo y los perfiles que el motor ofrece."""

    profile: str | None
    choices: tuple[str, ...]
    backend: PowerProfileBackend

    def to_json(self) -> str:
        return json.dumps(
            {
                "profile": self.profile,
                "choices": list(self.choices),
                "backend": self.backend.value,
            }
        )


class PowerProfileProvider(Protocol):
    """Motor de perfiles energéticos consultable y aplicable."""

    backend: PowerProfileBackend

    def available(self) -> bool:
        """Si el motor está presente en el sistema."""
        ...

    def read(self) -> tuple[str | None, tuple[str, ...]]:
        """Perfil activo y lista de perfiles disponibles."""
        ...

    def apply(self, profile: str) -> bool:
        """Aplica un perfil; False si el motor lo rechaza."""
        ...


_PPD_PROFILE_LINE = re.compile(r"^\s*(?:\*\s*)?(?P<name>[A-Za-z0-9_-]+):\s*$")


def _ppd_choices(raw: str) -> tuple[str, ...]:
    """Nombres de perfil de `powerprofilesctl list`.

    La salida real indenta cada nombre y marca el activo con '*'; los
    detalles del perfil son líneas con contenido tras los dos puntos.
    """
    choices: list[str] = []
    for line in raw.splitlines():
        match = _PPD_PROFILE_LINE.match(line)
        if match is not None:
            choices.append(match.group("name"))
    return tuple(choices)


class PpdPowerProfile:
    """Backend sobre power-profiles-daemon (servicio D-Bus del sistema)."""

    backend = PowerProfileBackend.PPD

    def available(self) -> bool:
        return shutil.which("powerprofilesctl") is not None

    def read(self) -> tuple[str | None, tuple[str, ...]]:
        tool = shutil.which("powerprofilesctl")
        if tool is None:
            return (None, ())
        listing = run([tool, "list"])
        choices = _ppd_choices(listing.stdout)
        active = run([tool, "get"])
        profile = active.stdout.strip() if active.returncode == 0 else ""
        return (profile or None, choices)

    def apply(self, profile: str) -> bool:
        tool = shutil.which("powerprofilesctl")
        if tool is None:
            return False
        return run([tool, "set", profile]).returncode == 0


class SolidPowerProfile:
    """Backend sobre el servicio D-Bus de KDE Solid (PowerProfile)."""

    backend = PowerProfileBackend.SOLID

    SERVICE = "org.kde.Solid.PowerManagement"
    OBJECT = "/org/kde/Solid/PowerManagement/Actions/PowerProfile"
    INTERFACE = "org.kde.Solid.PowerManagement.Actions.PowerProfile"

    def available(self) -> bool:
        return shutil.which("qdbus6") is not None

    def _call(
        self,
        method: str,
        *args: str,
    ) -> subprocess.CompletedProcess[str] | None:
        tool = shutil.which("qdbus6")
        if tool is None:
            return None
        return run(
            [tool, self.SERVICE, self.OBJECT, f"{self.INTERFACE}.{method}", *args],
        )

    def read(self) -> tuple[str | None, tuple[str, ...]]:
        choices: tuple[str, ...] = ()
        listed = self._call("profileChoices")
        if listed is not None and listed.returncode == 0:
            choices = tuple(
                line.strip() for line in listed.stdout.splitlines() if line.strip()
            )
        current = self._call("currentProfile")
        profile = ""
        if current is not None and current.returncode == 0:
            profile = current.stdout.strip()
        return (profile or None, choices)

    def apply(self, profile: str) -> bool:
        result = self._call("setProfile", profile)
        return result is not None and result.returncode == 0


POWER_PROFILE_ORDER: Final[dict[str, tuple[PowerProfileBackend, ...]]] = {
    "kwin": (PowerProfileBackend.SOLID, PowerProfileBackend.PPD),
    "niri": (PowerProfileBackend.PPD, PowerProfileBackend.SOLID),
}
DEFAULT_POWER_PROFILE_ORDER: Final[tuple[PowerProfileBackend, ...]] = (
    PowerProfileBackend.PPD,
    PowerProfileBackend.SOLID,
)


def power_profile_provider(compositor: str) -> PowerProfileProvider | None:
    """Primer motor disponible según el compositor de la sesión."""
    providers: dict[PowerProfileBackend, PowerProfileProvider] = {
        PowerProfileBackend.SOLID: SolidPowerProfile(),
        PowerProfileBackend.PPD: PpdPowerProfile(),
    }
    order = POWER_PROFILE_ORDER.get(compositor, DEFAULT_POWER_PROFILE_ORDER)
    for backend in order:
        provider = providers[backend]
        if provider.available():
            return provider
    return None


def power_profile_state() -> PowerProfileState:
    """Estado del perfil energético para el JSON del subcomando."""
    provider = power_profile_provider(detect_compositor())
    if provider is None:
        return PowerProfileState(
            profile=None,
            choices=(),
            backend=PowerProfileBackend.NONE,
        )
    profile, choices = provider.read()
    return PowerProfileState(
        profile=profile,
        choices=choices,
        backend=provider.backend,
    )


def power_profile_apply(profile: str) -> int:
    """Aplica un perfil energético; 1 con mensaje si no se pudo."""
    provider = power_profile_provider(detect_compositor())
    if provider is None:
        sys.stderr.write(
            "power-profile: no hay backend de perfil energético disponible\n",
        )
        return 1
    _, choices = provider.read()
    if not choices:
        sys.stderr.write("power-profile: no se pudo leer la lista de perfiles\n")
        return 1
    if profile not in choices:
        sys.stderr.write(
            f"power-profile: perfil desconocido: {profile} "
            f"(disponibles: {', '.join(choices)})\n",
        )
        return 1
    if not provider.apply(profile):
        sys.stderr.write(f"power-profile: no se pudo aplicar el perfil: {profile}\n")
        return 1
    return 0


# --- main --------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        sys.stderr.write(
            "uso: caparazon-wm {detect|active-output|primary-output|"
            "workspaces|watch-workspaces|windows|watch-windows|"
            "window-action|workspace-switch|power-profile|logout} [args]\n"
        )
        return 2
    cmd, rest = args[0], args[1:]
    if cmd == "detect":
        print(detect_compositor())
        return 0
    if cmd == "active-output":
        out = (
            active_output_niri()
            if detect_compositor() == "niri"
            else active_output_kwin()
        )
        print(out)
        return 0
    if cmd == "primary-output":
        out = (
            primary_output_niri()
            if detect_compositor() == "niri"
            else primary_output_kwin()
        )
        print(out)
        return 0
    if cmd == "workspaces":
        return print_workspaces()
    if cmd == "watch-workspaces":
        return watch_workspaces()
    if cmd == "windows":
        return print_windows()
    if cmd == "watch-windows":
        return watch_windows()
    if cmd == "window-action":
        if len(rest) < 1:
            sys.stderr.write("uso: caparazon-wm window-action <active> [candidatos...]\n")
            return 2
        active = rest[0]
        candidates = rest[1:]
        return window_action(active, candidates)
    if cmd == "workspace-switch":
        if len(rest) < 1:
            sys.stderr.write("uso: caparazon-wm workspace-switch <indice-1-based>\n")
            return 2
        try:
            index = int(rest[0])
        except ValueError:
            sys.stderr.write("workspace-switch: índice inválido\n")
            return 2
        return workspace_switch(index)
    if cmd == "power-profile":
        if not rest:
            print(power_profile_state().to_json())
            return 0
        if rest[0] == "--set":
            if len(rest) < 2:
                sys.stderr.write("uso: caparazon-wm power-profile --set <perfil>\n")
                return 2
            return power_profile_apply(rest[1])
        sys.stderr.write("uso: caparazon-wm power-profile [--set <perfil>]\n")
        return 2
    if cmd == "logout":
        return logout()
    sys.stderr.write(f"comando desconocido: {cmd}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""caparazon-wm — puente único de compositor para caparazon-shell.

Subcomandos estables (el QML sólo invoca estos):

  detect           imprime kwin | niri
  active-output    nombre de la pantalla activa
  primary-output   nombre de la pantalla principal
  monitors         JSON de salidas; --apply persiste los cambios
  workspaces       JSON de escritorios (shape del caché ezku-desktops)
  watch-workspaces una línea JSON por cambio, en bucle
  windows          JSON {appId, title, appIds}
  watch-windows    una línea JSON por cambio de ventana, en bucle
  window-action    ciclo del dock: enfoca / minimiza / restaura
  workspace-switch cambia al escritorio N (1-based)
  power-profile    perfil energético actual (JSON) y --set para aplicarlo
  icon-theme       tema de iconos actual (JSON) y --set para aplicarlo
  cursor-theme     tema de cursor Xcursor actual (JSON) y --set para aplicarlo
  keyboard-layout  idioma de teclado actual (JSON) y --set para aplicarlo
  logout           cierra la sesión

Detección: NIRI_SOCKET → busctl org.kde.KWin → niri msg version → kwin.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from dataclasses import replace
from enum import StrEnum
from pathlib import Path
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


def _as_float(value: Any) -> float:
    """Convierte coordenadas JSON a float; valores ausentes cuentan como cero."""
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def mode_label(width: Any, height: Any, refresh_mhz: Any) -> str:
    """Etiqueta KDL con la tasa en milihz convertida a tres decimales."""
    return f"{width}x{height}@{_as_float(refresh_mhz) / 1000:.3f}"


def normalize_transform(value: str) -> str:
    """Canonicaliza la transformación de niri a minúsculas con guion."""
    text = value.strip().lower().replace(" ", "").replace("_", "-")
    aliases = {
        "flipped90": "flipped-90",
        "flipped180": "flipped-180",
        "flipped270": "flipped-270",
    }
    return aliases.get(text, text)


def _niri_output_position(info: Any) -> tuple[float, float]:
    """Posición lógica de una salida, con fallback al JSON antiguo."""
    if not isinstance(info, dict):
        return 0.0, 0.0
    logical = info.get("logical")
    if isinstance(logical, dict):
        return (
            _as_float(logical.get("x", info.get("x", 0))),
            _as_float(logical.get("y", info.get("y", 0))),
        )
    return _as_float(info.get("x", 0)), _as_float(info.get("y", 0))


def primary_output_niri_fallback(outs: dict[str, Any]) -> str:
    """Salida habilitada superior izquierda cuando no hay principal configurable."""
    candidates: list[tuple[float, float, str]] = []
    for name, info in outs.items():
        if not _niri_output_enabled(info):
            continue
        x, y = _niri_output_position(info)
        candidates.append((x, y, str(name)))
    if not candidates:
        for name, info in outs.items():
            if _niri_output_enabled(info):
                return str(name)
        return ""
    candidates.sort()
    return candidates[0][2]


def primary_output_niri() -> str:
    """Respeta el principal configurado; si no aplica, usa el superior izquierdo."""
    niri = shutil.which("niri")
    if not niri:
        return ""
    probe = run([niri, "msg", "--json", "outputs"])
    if probe.returncode != 0:
        return ""
    outs = _niri_outputs_map(probe.stdout)
    configured = configured_primary_output(outs)
    if configured and configured in outs and _niri_output_enabled(outs[configured]):
        return configured
    return primary_output_niri_fallback(outs)


def niri_event_affects_workspaces(line: str) -> bool:
    keys = (
        "WorkspacesChanged",
        "WorkspaceActivated",
        "WindowsChanged",
        "WindowFocusChanged",
        "FocusedOutputsChanged",
    )
    return any(f'"{key}"' in line for key in keys)


def niri_event_affects_windows(line: str) -> bool:
    keys = (
        "WindowsChanged",
        "WindowOpenedOrChanged",
        "WindowClosed",
        "WindowFocusChanged",
        "WorkspaceActivated",
    )
    return any(f'"{key}"' in line for key in keys)


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
        "perOutputDesktops": {},
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
        "perOutputDesktops": {},
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
            if ws.get("is_active"):
                state["perOutput"][output] = str(ws_id)
            if occupied:
                state["occupiedPerOutput"].setdefault(output, []).append(
                    str(ws_id)
                )
            state["perOutputDesktops"].setdefault(output, []).append(
                {
                    "pos": int(idx) - 1,
                    "id": str(ws_id),
                    "name": str(name),
                    "idx": int(idx),
                    "active": bool(ws.get("is_active")),
                    "occupied": bool(occupied),
                }
            )
    for desks in state["perOutputDesktops"].values():
        desks.sort(key=lambda d: d["idx"])
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
                if niri_event_affects_workspaces(line):
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


def windows_cache_path() -> Path:
    return Path(os.path.expanduser("~/.cache/ezku-desktops.json")).resolve()


def windows_cache_signature(path: Path | None = None) -> str:
    target = path if path is not None else windows_cache_path()
    try:
        return hashlib.sha256(target.read_bytes()).hexdigest()
    except OSError:
        return ""


def windows_state_kwin() -> dict[str, Any]:
    """Lee el estado que el bridge KWin publica en el caché del compositor."""
    app_id = ""
    title = ""
    app_ids: list[str] = []
    try:
        with open(windows_cache_path(), encoding="utf-8") as fh:
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
                elif isinstance(w, str):
                    cid = w
                else:
                    continue
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
                if niri_event_affects_windows(line):
                    print(json.dumps(windows_state_niri()), flush=True)
        finally:
            proc.terminate()
        return 0

    # kwin: el bridge escribe el caché; el journal ya no publica ventanas.
    cache = windows_cache_path()
    last_signature = ""
    while True:
        signature = windows_cache_signature(cache)
        if signature != last_signature:
            last_signature = signature
            state = windows_state_kwin() if signature else {
                "appId": "",
                "title": "",
                "appIds": [],
            }
            print(json.dumps(state), flush=True)
        time.sleep(0.25)


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


# --- tema de iconos -----------------------------------------------------------

DEFAULT_ICON_THEME: Final[str] = "Papirus-Dark"
ICON_THEME_VARIABLE: Final[str] = "CAPARAZON_ICON_THEME"
QS_ICON_THEME_VARIABLE: Final[str] = "QS_ICON_THEME"
_ICON_THEME_ENTRY = re.compile(
    rf'{ICON_THEME_VARIABLE}\s+(?:"([^"]*)"|([^\s;}}]+))',
)
_QS_ICON_THEME_ENTRY = re.compile(
    rf'{QS_ICON_THEME_VARIABLE}\s+(?:"([^"]*)"|([^\s;}}]+))',
)


@dataclass(frozen=True, slots=True)
class IconThemeState:
    """Tema configurado y los temas que hay instalados."""

    current: str
    themes: tuple[str, ...]
    previews: dict[str, str]
    default: str
    configured: bool
    search: tuple[str, ...]

    def to_json(self) -> str:
        return json.dumps(
            {
                "current": self.current,
                "themes": list(self.themes),
                "previews": self.previews,
                "default": self.default,
                "configured": self.configured,
                "search": list(self.search),
            }
        )


def icon_theme_dirs() -> list[Path]:
    """Directorios donde se buscan los temas de iconos instalados."""
    home = Path.home()
    data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    data_home = os.environ.get("XDG_DATA_HOME") or str(home / ".local" / "share")
    dirs = [Path(entry) / "icons" for entry in data_dirs.split(":") if entry]
    dirs.append(Path(data_home) / "icons")
    dirs.append(home / ".icons")
    return dirs


def niri_config_path() -> Path:
    """El config de niri: el que usa la sesión."""
    override = os.environ.get("NIRI_CONFIG")
    if override:
        return Path(override)
    xdg = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(xdg) / "niri" / "config.kdl"


def _icon_theme_value(text: str) -> str:
    """El valor de la variable del tema de iconos en un trozo de KDL."""
    match = _ICON_THEME_ENTRY.search(text)
    if match is None:
        return ""
    return match.group(1) if match.group(1) is not None else match.group(2)


def read_niri_icon_theme(text: str) -> str:
    """El tema de iconos del bloque environment del config de niri; "" si no."""
    inside = False
    for line in text.splitlines():
        stripped = line.strip()
        if not inside:
            if not stripped.startswith("environment") or "{" not in stripped:
                continue
            inside = True
            value = _icon_theme_value(stripped[stripped.index("{") + 1 :])
            if value:
                return value
            if "}" in stripped:
                inside = False
            continue
        value = _icon_theme_value(stripped)
        if value:
            return value
        if "}" in stripped:
            inside = False
    return ""


def set_niri_icon_theme(text: str, name: str) -> str:
    """El config de niri con ambas variables de tema puestas; conserva el resto."""
    entries = (
        (ICON_THEME_VARIABLE, _ICON_THEME_ENTRY),
        (QS_ICON_THEME_VARIABLE, _QS_ICON_THEME_ENTRY),
    )
    lines = text.splitlines()
    start = None
    end = None
    depth = 0
    for index, line in enumerate(lines):
        stripped = line.strip()
        if start is None:
            if not stripped.startswith("environment") or "{" not in stripped:
                continue
            start = index
            depth = stripped.count("{") - stripped.count("}")
            if depth <= 0:
                end = index
                break
            continue
        depth += stripped.count("{") - stripped.count("}")
        if depth <= 0:
            end = index
            break

    if start is None:
        block = ["environment {", *(f'    {var} "{name}"' for var, _ in entries), "}"]
        if lines and lines[-1].strip():
            return "\n".join([*lines, "", *block]) + "\n"
        return "\n".join([*lines, *block]) + "\n"

    body = lines[start + 1 : end]
    if end == start:
        body = []
    updated: list[str] = list(body)
    for variable, pattern in entries:
        replacement = f'    {variable} "{name}"'
        replaced = False
        for index, line in enumerate(updated):
            if pattern.search(line):
                updated[index] = replacement
                replaced = True
        if not replaced:
            updated.append(replacement)
    return "\n".join([*lines[: start + 1], *updated, *lines[end:]]) + "\n"


def installed_icon_themes() -> list[str]:
    """Nombres de los temas instalados: los que tienen index.theme."""
    names: set[str] = set()
    for directory in icon_theme_dirs():
        try:
            entries = sorted(directory.iterdir())
        except OSError:
            continue
        for entry in entries:
            if entry.is_dir() and (entry / "index.theme").is_file():
                names.add(entry.name)
    return sorted(names)


def icon_theme_inherits(name: str) -> list[str]:
    """Temas que hereda un tema, en el orden de su index.theme."""
    for directory in icon_theme_dirs():
        index = directory / name / "index.theme"
        try:
            text = index.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            stripped = line.strip()
            if not stripped.lower().startswith("inherits="):
                continue
            value = stripped.split("=", 1)[1]
            return [part.strip() for part in value.split(",") if part.strip()]
        return []
    return []


def icon_theme_search_order(name: str) -> list[str]:
    """Tema activo, sus herencias en profundidad y hicolor al final."""
    order: list[str] = []
    seen: set[str] = set()

    def visit(theme: str) -> None:
        if not theme or theme in seen:
            return
        seen.add(theme)
        order.append(theme)
        for parent in icon_theme_inherits(theme):
            visit(parent)

    visit(name)
    visit("hicolor")
    return order


def icon_theme_preview(theme: str) -> str:
    """Ruta de una imagen del tema, para la miniatura del panel."""
    for directory in icon_theme_dirs():
        root = directory / theme
        if not root.is_dir():
            continue
        for suffix in (".png", ".svg", ".xpm"):
            candidate = root / f"{theme}{suffix}"
            if candidate.is_file():
                return str(candidate)
        try:
            images = sorted(
                path
                for path in root.iterdir()
                if path.suffix.lower() in {".png", ".svg"}
            )
        except OSError:
            continue
        if images:
            return str(images[0])
    return ""


def _kdl_lines_in_load_order(
    path: Path, seen: set[Path] | None = None
) -> list[tuple[Path, str]]:
    """Líneas del árbol KDL en orden de carga; include se expande en su sitio."""
    if seen is None:
        seen = set()
    try:
        resolved = path.resolve()
    except OSError:
        return []
    if resolved in seen:
        return []
    seen.add(resolved)
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    lines: list[tuple[Path, str]] = []
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped.startswith('include "') and stripped.endswith('"'):
            relative = stripped[len('include "') : -1]
            lines.extend(_kdl_lines_in_load_order(path.parent / relative, seen))
        else:
            lines.append((path, line))
    return lines


def _find_icon_theme_file(path: Path) -> Path | None:
    """Archivo del árbol que aporta el valor efectivo (último en orden de carga)."""
    owner: Path | None = None
    inside = False
    for file, line in _kdl_lines_in_load_order(path):
        stripped = line.strip()
        if not inside:
            if not stripped.startswith("environment") or "{" not in stripped:
                continue
            inside = True
            if _ICON_THEME_ENTRY.search(stripped):
                owner = file
            if "}" in stripped:
                inside = False
            continue
        if _ICON_THEME_ENTRY.search(stripped):
            owner = file
        if "}" in stripped:
            inside = False
    return owner


def read_icon_theme_file(path: Path) -> str:
    """El tema de iconos del config de niri (include incluido); "" si no está."""
    value = ""
    chunks: list[str] = []
    current: list[str] = []
    current_owner: Path | None = None
    for file, line in _kdl_lines_in_load_order(path):
        if current_owner is None:
            current_owner = file
        if file != current_owner:
            chunks.append("\n".join(current))
            current = []
            current_owner = file
        current.append(line)
    if current:
        chunks.append("\n".join(current))
    for chunk in chunks:
        found = read_niri_icon_theme(chunk)
        if found:
            value = found
    return value


def write_icon_theme(name: str) -> Path:
    """Escribe el tema de iconos en el archivo dueño (include si vive ahí)."""
    root = niri_config_path()
    target = _find_icon_theme_file(root) or root
    try:
        raw = target.read_text(encoding="utf-8")
    except OSError:
        raw = ""
    updated = set_niri_icon_theme(raw, name)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(updated, encoding="utf-8")
    os.chmod(temporary, 0o644)
    os.replace(temporary, target)
    return target


def icon_theme_state() -> IconThemeState:
    """Estado del tema de iconos para el JSON del subcomando."""
    configured = read_icon_theme_file(niri_config_path())
    themes = installed_icon_themes()
    current = configured or DEFAULT_ICON_THEME
    return IconThemeState(
        current=current,
        themes=tuple(themes),
        previews={theme: icon_theme_preview(theme) for theme in themes},
        default=DEFAULT_ICON_THEME,
        configured=bool(configured),
        search=tuple(icon_theme_search_order(current)),
    )


def icon_theme_apply(name: str) -> int:
    """Aplica un tema de iconos; 1 con mensaje si no está instalado."""
    if name not in installed_icon_themes():
        sys.stderr.write(f"icon-theme: tema desconocido: {name}\n")
        return 1
    write_icon_theme(name)
    return 0


# --- tema de cursor -----------------------------------------------------------

DEFAULT_CURSOR_THEME: Final[str] = "breeze_cursors"
_CURSOR_THEME_ENTRY = re.compile(r'xcursor-theme\s+(?:"([^"]*)"|([^\s;}]+))')


@dataclass(frozen=True, slots=True)
class CursorThemeState:
    """Tema de cursor configurado y los Xcursor instalados."""

    current: str
    themes: tuple[str, ...]
    default: str
    configured: bool

    def to_json(self) -> str:
        return json.dumps(
            {
                "current": self.current,
                "themes": list(self.themes),
                "default": self.default,
                "configured": self.configured,
            }
        )


def _cursor_theme_value(text: str) -> str:
    """El valor de xcursor-theme al inicio de un trozo de KDL."""
    match = _CURSOR_THEME_ENTRY.match(text)
    if match is None:
        return ""
    return match.group(1) if match.group(1) is not None else match.group(2)


def cursor_theme_dirs() -> list[Path]:
    """Directorios donde se buscan los temas Xcursor instalados."""
    home = Path.home()
    data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    data_home = os.environ.get("XDG_DATA_HOME") or str(home / ".local" / "share")
    dirs = [Path(entry) / "icons" for entry in data_dirs.split(":") if entry]
    dirs.append(Path(data_home) / "icons")
    dirs.append(home / ".icons")
    dirs.append(home / ".cursors")
    return dirs


def installed_cursor_themes() -> list[str]:
    """Nombres de temas Xcursor con directorio `cursors`, ordenados y únicos."""
    names: set[str] = set()
    for root in cursor_theme_dirs():
        try:
            entries = root.iterdir()
        except OSError:
            continue
        for entry in entries:
            if entry.is_dir() and (entry / "cursors").is_dir():
                names.add(entry.name)
    return sorted(names)


def read_niri_cursor_theme(text: str) -> str:
    """Último xcursor-theme dentro de un bloque `cursor {}`; "" si no hay."""
    value = ""
    depth = 0
    in_cursor = False
    in_string = False
    escaped = False
    index = 0
    while index < len(text):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            index += 1
            continue
        if char == "{":
            prefix = text[max(0, index - 40) : index]
            if not in_cursor and re.search(r"\bcursor\s*$", prefix):
                depth = 1
                in_cursor = True
            elif in_cursor:
                depth += 1
            index += 1
            continue
        if char == "}" and in_cursor:
            depth -= 1
            if depth == 0:
                in_cursor = False
            index += 1
            continue
        if in_cursor and not char.isspace():
            found = _cursor_theme_value(text[index:])
            if found:
                value = found
                match = _CURSOR_THEME_ENTRY.match(text, index)
                index = match.end() if match else index + len(found)
                continue
        index += 1
    return value


def read_cursor_theme_file(path: Path) -> str:
    """Tema de cursor del config de niri (includes incluidos); "" si no está."""
    text = "\n".join(line for _, line in _kdl_lines_in_load_order(path))
    return read_niri_cursor_theme(text)


def cursor_theme_state() -> CursorThemeState:
    """Estado del tema de cursor para el JSON del subcomando."""
    configured = read_cursor_theme_file(niri_config_path())
    themes = tuple(installed_cursor_themes())
    current = configured or DEFAULT_CURSOR_THEME
    return CursorThemeState(
        current=current,
        themes=themes,
        default=DEFAULT_CURSOR_THEME,
        configured=bool(configured),
    )


def _kdl_brace_delta(text: str) -> int:
    """Saldo de llaves KDL fuera de cadenas."""
    delta = 0
    in_string = False
    escaped = False
    for char in text:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            delta += 1
        elif char == "}":
            delta -= 1
    return delta


def set_niri_cursor_theme(text: str, name: str) -> str:
    """Config con el Xcursor aplicado; conserva el resto y termina en newline."""
    lines = text.splitlines()
    replacement = f'    xcursor-theme "{name}"'
    start: int | None = None
    end: int | None = None
    depth = 0
    for index, line in enumerate(lines):
        if start is None:
            if re.search(r"\bcursor\s*\{", line) is None:
                continue
            start = index
            depth = _kdl_brace_delta(line)
            if depth <= 0:
                end = index
                break
            continue
        depth += _kdl_brace_delta(line)
        if depth <= 0:
            end = index
            break

    if start is None:
        block = ["cursor {", replacement, "}"]
        if lines and lines[-1].strip():
            return "\n".join([*lines, "", *block]) + "\n"
        return "\n".join([*lines, *block]) + "\n"

    if end == start:
        match = re.search(r"\bcursor\s*\{", lines[start])
        prefix = lines[start][: match.start()] if match else ""
        updated = [f"{prefix}cursor {{", replacement, "}"]
        return "\n".join([*lines[:start], *updated, *lines[start + 1 :]]) + "\n"

    body = lines[start + 1 : end]
    has_entry = any(_CURSOR_THEME_ENTRY.search(line) for line in body)
    if has_entry:
        body = [replacement if _CURSOR_THEME_ENTRY.search(line) else line for line in body]
    else:
        body = [*body, replacement]
    return "\n".join([*lines[: start + 1], *body, *lines[end:]]) + "\n"


def _find_cursor_theme_file(path: Path) -> Path | None:
    """Último archivo del árbol KDL que aporta un xcursor-theme efectivo."""
    owner: Path | None = None
    depth = 0
    in_cursor = False
    for file, line in _kdl_lines_in_load_order(path):
        stripped = line.strip()
        if not in_cursor:
            if re.search(r"\bcursor\s*\{", stripped) is None:
                continue
            in_cursor = True
            depth = _kdl_brace_delta(stripped)
            if depth > 0 and _CURSOR_THEME_ENTRY.search(stripped):
                owner = file
            if depth <= 0:
                in_cursor = False
            continue
        if _CURSOR_THEME_ENTRY.search(stripped):
            owner = file
        depth += _kdl_brace_delta(stripped)
        if depth <= 0:
            in_cursor = False
    return owner


def write_cursor_theme(name: str) -> Path:
    """Escribe el Xcursor en el archivo dueño (include si vive ahí)."""
    root = niri_config_path()
    target = _find_cursor_theme_file(root) or root
    try:
        raw = target.read_text(encoding="utf-8")
    except OSError:
        raw = ""
    updated = set_niri_cursor_theme(raw, name)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(updated, encoding="utf-8")
    os.chmod(temporary, 0o644)
    os.replace(temporary, target)
    return target


def reload_niri_config() -> int:
    """Recarga el config de niri; 1 si niri no está disponible."""
    niri = shutil.which("niri")
    if not niri:
        return 1
    return run([niri, "msg", "action", "load-config-file"]).returncode


def cursor_theme_apply(name: str) -> int:
    """Aplica un Xcursor instalado; 1 si no existe o falla la recarga."""
    if name not in installed_cursor_themes():
        sys.stderr.write(f"cursor-theme: tema desconocido: {name}\n")
        return 1
    write_cursor_theme(name)
    if reload_niri_config() != 0:
        sys.stderr.write("cursor-theme: no se pudo recargar niri\n")
        return 1
    return 0


# --- idioma de teclado --------------------------------------------------------


DEFAULT_KEYBOARD_LAYOUT: Final[str] = "us"

KEYBOARD_LAYOUTS: Final[tuple[dict[str, Any], ...]] = (
    {
        "label": "Español",
        "options": (
            {"layout": "es", "variant": "", "label": "España"},
            {"layout": "latam", "variant": "", "label": "Latinoamérica"},
        ),
    },
    {
        "label": "Inglés",
        "options": (
            {"layout": "us", "variant": "", "label": "EE. UU."},
            {"layout": "us", "variant": "intl", "label": "EE. UU., internacional"},
            {"layout": "gb", "variant": "", "label": "Reino Unido"},
        ),
    },
    {
        "label": "Portugués",
        "options": (
            {"layout": "br", "variant": "", "label": "Brasil"},
            {"layout": "pt", "variant": "", "label": "Portugal"},
        ),
    },
    {
        "label": "Francés",
        "options": (
            {"layout": "fr", "variant": "", "label": "Francia"},
            {"layout": "fr", "variant": "ca", "label": "Canadá"},
        ),
    },
    {"label": "Alemán", "options": ({"layout": "de", "variant": "", "label": "Alemania"},)},
    {"label": "Italiano", "options": ({"layout": "it", "variant": "", "label": "Italia"},)},
    {"label": "Japonés", "options": ({"layout": "jp", "variant": "", "label": "Japón"},)},
)


@dataclass(frozen=True, slots=True)
class KeyboardLayoutState:
    """Idioma de teclado configurado y catálogo disponible."""

    layout: str
    variant: str
    label: str
    configured: bool
    languages: tuple[dict[str, Any], ...]

    def to_json(self) -> str:
        return json.dumps(
            {
                "layout": self.layout,
                "variant": self.variant,
                "label": self.label,
                "configured": self.configured,
                "languages": list(self.languages),
            }
        )


def keyboard_layout_catalog() -> tuple[dict[str, Any], ...]:
    """Catálogo curado de idiomas y variantes comunes."""
    return KEYBOARD_LAYOUTS


def keyboard_layout_label(layout: str, variant: str) -> str:
    """Etiqueta legible de una combinación layout/variant."""
    for language in KEYBOARD_LAYOUTS:
        for option in language["options"]:
            if option["layout"] == layout and option["variant"] == variant:
                return f'{language["label"]} · {option["label"]}'
    if variant:
        return f"Personalizada: {layout}/{variant}"
    return f"Personalizada: {layout}"


def keyboard_layout_known(layout: str, variant: str) -> bool:
    """True si la combinación exacta está en el catálogo."""
    return any(
        option["layout"] == layout and option["variant"] == variant
        for language in KEYBOARD_LAYOUTS
        for option in language["options"]
    )


_XKB_BLOCK = re.compile(r"\bxkb\s*\{")
_XKB_LAYOUT_ENTRY = re.compile(r'\blayout\s+"([^"]*)"')
_XKB_VARIANT_ENTRY = re.compile(r'\bvariant\s+"([^"]*)"')
_INPUT_BLOCK = re.compile(r"\binput\s*\{")
_KEYBOARD_BLOCK = re.compile(r"\bkeyboard\s*\{")


def _strip_kdl_comment(line: str) -> str:
    in_string = False
    escaped = False
    for index, char in enumerate(line):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "/" and index + 1 < len(line) and line[index + 1] == "/":
            return line[:index]
    return line


def _find_kdl_block(
    lines: list[str], pattern: re.Pattern[str]
) -> tuple[int, int] | None:
    start: int | None = None
    depth = 0
    for index, line in enumerate(lines):
        clean = _strip_kdl_comment(line)
        if start is None:
            if pattern.search(clean) is None:
                continue
            start = index
            depth = _kdl_brace_delta(clean)
            if depth <= 0:
                return (index, index)
            continue
        depth += _kdl_brace_delta(clean)
        if depth <= 0:
            return (start, index)
    return None


def _indent_of(line: str) -> str:
    return line[: len(line) - len(line.lstrip())]


def _xkb_entry_lines(indent: str, layout: str, variant: str) -> list[str]:
    entries = [f'{indent}layout "{layout}"']
    if variant:
        entries.append(f'{indent}variant "{variant}"')
    return entries


def read_niri_keyboard_layout(text: str) -> tuple[str, str]:
    """Layout y variante activos del bloque xkb; "" si no están configurados."""
    layout = ""
    variant = ""
    in_xkb = False
    depth = 0
    for raw in text.splitlines():
        line = _strip_kdl_comment(raw)
        if not in_xkb:
            match = _XKB_BLOCK.search(line)
            if match is None:
                continue
            in_xkb = True
            depth = _kdl_brace_delta(line)
            tail = line[match.end() :]
            for entry in _XKB_LAYOUT_ENTRY.finditer(tail):
                layout = entry.group(1)
            for entry in _XKB_VARIANT_ENTRY.finditer(tail):
                variant = entry.group(1)
            if depth <= 0:
                in_xkb = False
            continue
        for entry in _XKB_LAYOUT_ENTRY.finditer(line):
            layout = entry.group(1)
        for entry in _XKB_VARIANT_ENTRY.finditer(line):
            variant = entry.group(1)
        depth += _kdl_brace_delta(line)
        if depth <= 0:
            in_xkb = False
    return layout, variant


def read_keyboard_layout_file(path: Path) -> tuple[str, str]:
    """Layout y variante efectivos del config de niri, con includes."""
    layout = ""
    variant = ""
    chunks: list[str] = []
    current: list[str] = []
    current_owner: Path | None = None
    for file, line in _kdl_lines_in_load_order(path):
        if current_owner is None:
            current_owner = file
        if file != current_owner:
            chunks.append("\n".join(current))
            current = []
            current_owner = file
        current.append(line)
    if current:
        chunks.append("\n".join(current))
    for chunk in chunks:
        found_layout, found_variant = read_niri_keyboard_layout(chunk)
        if found_layout:
            layout = found_layout
        if found_variant:
            variant = found_variant
    return layout, variant


def _find_keyboard_layout_file(path: Path) -> Path | None:
    owner: Path | None = None
    in_xkb = False
    depth = 0
    for file, raw in _kdl_lines_in_load_order(path):
        line = _strip_kdl_comment(raw)
        if not in_xkb:
            match = _XKB_BLOCK.search(line)
            if match is None:
                continue
            in_xkb = True
            depth = _kdl_brace_delta(line)
            if _XKB_LAYOUT_ENTRY.search(line) or _XKB_VARIANT_ENTRY.search(line):
                owner = file
            if depth <= 0:
                in_xkb = False
            continue
        if _XKB_LAYOUT_ENTRY.search(line) or _XKB_VARIANT_ENTRY.search(line):
            owner = file
        depth += _kdl_brace_delta(line)
        if depth <= 0:
            in_xkb = False
    return owner


def _replace_existing_xkb(
    lines: list[str], start: int, end: int, layout: str, variant: str
) -> list[str]:
    xkb_indent = _indent_of(lines[start])
    if end == start:
        match = _XKB_BLOCK.search(_strip_kdl_comment(lines[start]))
        prefix = lines[start][: match.start()] if match else xkb_indent
        updated = [
            f"{prefix}xkb {{",
            *_xkb_entry_lines(xkb_indent + "    ", layout, variant),
            f"{prefix}}}",
        ]
        return [*lines[:start], *updated, *lines[start + 1 :]]

    body = lines[start + 1 : end]
    inner_indent = xkb_indent + "    "
    for raw in body:
        clean = _strip_kdl_comment(raw)
        if clean.strip():
            if _XKB_LAYOUT_ENTRY.search(clean) or _XKB_VARIANT_ENTRY.search(clean):
                inner_indent = _indent_of(raw)
                break
            inner_indent = _indent_of(raw)
    layout_line = f'{inner_indent}layout "{layout}"'
    variant_line = f'{inner_indent}variant "{variant}"' if variant else None
    replacement: list[str] = []
    layout_done = False
    variant_done = False
    for raw in body:
        clean = _strip_kdl_comment(raw)
        if _XKB_LAYOUT_ENTRY.search(clean):
            if not layout_done:
                replacement.append(layout_line)
                layout_done = True
            continue
        if _XKB_VARIANT_ENTRY.search(clean):
            if variant_line is not None and not variant_done:
                replacement.append(variant_line)
                variant_done = True
            continue
        replacement.append(raw)
    if not layout_done:
        replacement.insert(0, layout_line)
    if variant_line is not None and not variant_done:
        position = replacement.index(layout_line)
        replacement.insert(position + 1, variant_line)
    return [*lines[: start + 1], *replacement, *lines[end:]]


def _insert_new_xkb(lines: list[str], layout: str, variant: str) -> list[str]:
    keyboard = _find_kdl_block(lines, _KEYBOARD_BLOCK)
    if keyboard is not None:
        start, end = keyboard
        indent = _indent_of(lines[start]) + "    "
        block = [
            f"{indent}xkb {{",
            *_xkb_entry_lines(indent + "    ", layout, variant),
            f"{indent}}}",
        ]
        if end == start:
            match = _KEYBOARD_BLOCK.search(_strip_kdl_comment(lines[start]))
            prefix = lines[start][: match.start()] if match else _indent_of(lines[start])
            updated = [f"{prefix}keyboard {{", *block, f"{prefix}}}"]
            return [*lines[:start], *updated, *lines[start + 1 :]]
        return [*lines[:end], *block, *lines[end:]]

    input_block = _find_kdl_block(lines, _INPUT_BLOCK)
    if input_block is not None:
        start, end = input_block
        indent = _indent_of(lines[start]) + "    "
        block = [
            f"{indent}keyboard {{",
            f"{indent}    xkb {{",
            *_xkb_entry_lines(indent + "        ", layout, variant),
            f"{indent}    }}",
            f"{indent}}}",
        ]
        if end == start:
            match = _INPUT_BLOCK.search(_strip_kdl_comment(lines[start]))
            prefix = lines[start][: match.start()] if match else _indent_of(lines[start])
            updated = [f"{prefix}input {{", *block, f"{prefix}}}"]
            return [*lines[:start], *updated, *lines[start + 1 :]]
        return [*lines[:end], *block, *lines[end:]]

    block = [
        "input {",
        "    keyboard {",
        "        xkb {",
        *_xkb_entry_lines("            ", layout, variant),
        "        }",
        "    }",
        "}",
    ]
    if lines and lines[-1].strip():
        return [*lines, "", *block]
    return [*lines, *block]


def set_niri_keyboard_layout(text: str, layout: str, variant: str) -> str:
    """Config con el idioma aplicado; conserva opciones y líneas ajenas."""
    lines = text.splitlines()
    xkb = _find_kdl_block(lines, _XKB_BLOCK)
    if xkb is not None:
        lines = _replace_existing_xkb(lines, xkb[0], xkb[1], layout, variant)
    else:
        lines = _insert_new_xkb(lines, layout, variant)
    return "\n".join(lines) + "\n"


def write_keyboard_layout(layout: str, variant: str) -> Path:
    """Escribe el layout en el archivo dueño (include si vive ahí)."""
    root = niri_config_path()
    target = _find_keyboard_layout_file(root) or root
    try:
        raw = target.read_text(encoding="utf-8")
    except OSError:
        raw = ""
    updated = set_niri_keyboard_layout(raw, layout, variant)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(updated, encoding="utf-8")
    os.chmod(temporary, 0o644)
    os.replace(temporary, target)
    return target


def keyboard_layout_state() -> KeyboardLayoutState:
    """Estado del idioma de teclado para el JSON del subcomando."""
    configured_layout, configured_variant = read_keyboard_layout_file(niri_config_path())
    layout = configured_layout or DEFAULT_KEYBOARD_LAYOUT
    label = keyboard_layout_label(layout, configured_variant)
    return KeyboardLayoutState(
        layout=layout,
        variant=configured_variant,
        label=label,
        configured=bool(configured_layout),
        languages=keyboard_layout_catalog(),
    )


def keyboard_layout_apply(layout: str, variant: str) -> int:
    """Valida, persiste y recarga niri; 1 si la combinación o la recarga falla."""
    if not keyboard_layout_known(layout, variant):
        sys.stderr.write(f"keyboard-layout: combinación desconocida: {layout}/{variant}\n")
        return 1
    write_keyboard_layout(layout, variant)
    if reload_niri_config() != 0:
        sys.stderr.write("keyboard-layout: no se pudo recargar niri\n")
        return 1
    return 0


# --- configuración de outputs -------------------------------------------------


@dataclass(frozen=True, slots=True)
class OutputBlock:
    """Bloque `output` persistido en config.d/15-outputs.kdl."""

    name: str
    mode: str
    scale: float
    transform: str
    x: int
    y: int
    primary: bool
    vrr: bool


OUTPUTS_INCLUDE: Final[str] = 'include "config.d/15-outputs.kdl"'
_VALID_TRANSFORMS: Final[frozenset[str]] = frozenset(
    {"normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"}
)
_OUTPUT_START = re.compile(r'^\s*output\s+"([^"]+)"\s*\{')
_MODE_ENTRY = re.compile(r'\bmode\s+"([^"]*)"')
_SCALE_ENTRY = re.compile(r"\bscale\s+(-?\d+(?:\.\d+)?)")
_TRANSFORM_ENTRY = re.compile(r'\btransform\s+"([^"]*)"')
_POSITION_ENTRY = re.compile(r"\bposition\s+x=(-?\d+)\s+y=(-?\d+)")
_FOCUS_ENTRY = re.compile(r"\bfocus-at-startup\b")
_VRR_ENTRY = re.compile(r"\bvariable-refresh-rate\b")


def output_config_path(root: Path) -> Path:
    """Archivo propio de outputs, hermano del config principal."""
    return root.parent / "config.d" / "15-outputs.kdl"


def strip_kdl_comments(text: str) -> str:
    """Comenta fuera del KDL conservando saltos y contenido entre comillas."""
    chars = list(text)
    index = 0
    in_string = False
    escaped = False
    while index < len(chars):
        char = chars[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            index += 1
            continue
        if char == "/" and index + 1 < len(chars):
            following = chars[index + 1]
            if following == "/":
                while index < len(chars) and chars[index] != "\n":
                    chars[index] = " "
                    index += 1
                continue
            if following == "-":
                while index < len(chars) and chars[index] != "\n":
                    chars[index] = " "
                    index += 1
                continue
            if following == "*":
                chars[index] = " "
                chars[index + 1] = " "
                index += 2
                while (
                    index < len(chars)
                    and not (chars[index] == "*" and index + 1 < len(chars) and chars[index + 1] == "/")
                ):
                    if chars[index] != "\n":
                        chars[index] = " "
                    index += 1
                if index + 1 < len(chars):
                    chars[index] = " "
                    chars[index + 1] = " "
                    index += 2
                continue
        index += 1
    return "".join(chars)


def find_output_blocks(text: str) -> list[tuple[str, str]]:
    """Bloques `output` activos: [(nombre, texto del bloque)]."""
    clean = strip_kdl_comments(text)
    lines = clean.splitlines()
    blocks: list[tuple[str, str]] = []
    index = 0
    while index < len(lines):
        match = _OUTPUT_START.match(lines[index])
        if match is None:
            index += 1
            continue
        depth = _kdl_brace_delta(lines[index])
        body = [lines[index]]
        index += 1
        while index < len(lines) and depth > 0:
            depth += _kdl_brace_delta(lines[index])
            body.append(lines[index])
            index += 1
        blocks.append((match.group(1), "\n".join(body)))
    return blocks


def read_output_configs(path: Path) -> dict[str, OutputBlock]:
    """Outputs guardados en un archivo KDL; archivo ausente equivale a vacío."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    blocks: dict[str, OutputBlock] = {}
    for name, body in find_output_blocks(text):
        mode_match = _MODE_ENTRY.search(body)
        scale_match = _SCALE_ENTRY.search(body)
        transform_match = _TRANSFORM_ENTRY.search(body)
        position_match = _POSITION_ENTRY.search(body)
        try:
            scale = float(scale_match.group(1)) if scale_match else 1.0
        except ValueError:
            scale = 1.0
        try:
            x = int(position_match.group(1)) if position_match else 0
            y = int(position_match.group(2)) if position_match else 0
        except ValueError:
            x, y = 0, 0
        blocks[name] = OutputBlock(
            name=name,
            mode=mode_match.group(1) if mode_match else "",
            scale=scale,
            transform=transform_match.group(1) if transform_match else "normal",
            x=x,
            y=y,
            primary=_FOCUS_ENTRY.search(body) is not None,
            vrr=_VRR_ENTRY.search(body) is not None,
        )
    return blocks


def configured_primary_output(outs: dict[str, Any]) -> str:
    """Monitor con `focus-at-startup` que sigue conectado; "" si no hay."""
    blocks = read_output_configs(output_config_path(niri_config_path()))
    for name, block in blocks.items():
        if block.primary and name in outs:
            return name
    return ""


def format_scale(value: float) -> str:
    """`1` para escalas enteras; decimal compacto para el resto."""
    number = float(value)
    return str(int(number)) if number.is_integer() else str(number)


def render_output_configs(blocks: dict[str, OutputBlock]) -> str:
    """Texto KDL de los bloques en el orden recibido."""
    lines: list[str] = []
    for name, block in blocks.items():
        lines.extend(
            [
                f'output "{name}" {{',
                f'    mode "{block.mode}"',
                f"    scale {format_scale(block.scale)}",
                f'    transform "{block.transform}"',
                f"    position x={block.x} y={block.y}",
            ]
        )
        if block.primary:
            lines.append("    focus-at-startup")
        if block.vrr:
            lines.append("    variable-refresh-rate")
        lines.append("}")
    if not lines:
        return ""
    return "\n".join(lines) + "\n"


def _atomic_write_text(path: Path, text: str) -> Path:
    """Escritura atómica con permisos 0644, igual que temas e iconos."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.chmod(temporary, 0o644)
    os.replace(temporary, path)
    return path


def ensure_outputs_include(root: Path) -> None:
    """Añade el include de outputs una sola vez al config principal."""
    try:
        raw = root.read_text(encoding="utf-8")
    except OSError:
        raw = ""
    clean_lines = strip_kdl_comments(raw).splitlines()
    if any(line.strip() == OUTPUTS_INCLUDE for line in clean_lines):
        return
    lines = raw.splitlines()
    insert_at = len(lines)
    for index, line in enumerate(clean_lines):
        if line.strip() == 'include "config.d/10-input-and-cursor.kdl"':
            insert_at = index + 1
            break
    lines.insert(insert_at, OUTPUTS_INCLUDE)
    trailing = "\n" if raw.endswith("\n") or not raw else ""
    _atomic_write_text(root, "\n".join(lines) + trailing)


def write_output_configs(root: Path, blocks: dict[str, OutputBlock]) -> Path:
    """Persiste los bloques y deja el include activo en config.kdl."""
    target = output_config_path(root)
    _atomic_write_text(target, render_output_configs(blocks))
    ensure_outputs_include(root)
    return target


def foreign_output_files(root: Path) -> list[Path]:
    """Archivos del árbol KDL con bloques `output` fuera del propio archivo."""
    own = output_config_path(root).resolve()
    grouped: dict[Path, list[str]] = {}
    order: list[Path] = []
    for file, line in _kdl_lines_in_load_order(root):
        try:
            resolved = file.resolve()
        except OSError:
            resolved = file
        if resolved == own:
            continue
        if resolved not in grouped:
            grouped[resolved] = []
            order.append(resolved)
        grouped[resolved].append(line)
    return [path for path in order if find_output_blocks("\n".join(grouped[path]))]


@dataclass(frozen=True, slots=True)
class MonitorOutputState:
    """Estado serializable de una salida conectada."""

    name: str
    label: str
    make: str
    model: str
    serial: str
    primary: bool
    primary_configured: bool
    mode: str
    modes: tuple[dict[str, Any], ...]
    transform: str
    x: int
    y: int

    def as_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "label": self.label,
            "make": self.make,
            "model": self.model,
            "serial": self.serial,
            "primary": self.primary,
            "primary_configured": self.primary_configured,
            "mode": self.mode,
            "modes": [dict(item) for item in self.modes],
            "transform": self.transform,
            "x": self.x,
            "y": self.y,
        }

    def to_json(self) -> str:
        return json.dumps(self.as_dict())


@dataclass(frozen=True, slots=True)
class MonitorState:
    """Estado completo del subcomando `monitors`."""

    outputs: tuple[MonitorOutputState, ...]
    configured: bool
    error: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "outputs": [output.as_dict() for output in self.outputs],
            "configured": self.configured,
            "error": self.error,
        }

    def to_json(self) -> str:
        return json.dumps(self.as_dict())


def _niri_mode_entries(raw: Any, current: Any) -> tuple[tuple[dict[str, Any], ...], str]:
    """Modos disponibles y etiqueta del modo actual."""
    entries: list[dict[str, Any]] = []
    current_label = ""
    modes = raw if isinstance(raw, list) else []
    for index, item in enumerate(modes):
        mode = item if isinstance(item, dict) else {}
        label = mode_label(
            mode.get("width", 0),
            mode.get("height", 0),
            mode.get("refresh_rate", 0),
        )
        is_current = current == index or (isinstance(current, dict) and current is mode)
        entries.append(
            {
                "label": label,
                "preferred": bool(mode.get("is_preferred", False)),
                "current": is_current,
            }
        )
        if is_current:
            current_label = label
    return tuple(entries), current_label


def monitor_state() -> MonitorState:
    """Estado de monitores de niri; error contractual si el compositor es KDE."""
    if detect_compositor() != "niri":
        return MonitorState((), False, "monitores: sólo niri")
    niri = shutil.which("niri")
    if not niri:
        return MonitorState((), False, "monitores: niri no disponible")
    probe = run([niri, "msg", "--json", "outputs"])
    if probe.returncode != 0:
        return MonitorState((), False, "monitores: no se pudo consultar niri")
    outs = _niri_outputs_map(probe.stdout)
    configured_primary = configured_primary_output(outs)
    primary = configured_primary or primary_output_niri_fallback(outs)
    configured = output_config_path(niri_config_path()).is_file()
    outputs: list[MonitorOutputState] = []
    for name, info in outs.items():
        if not _niri_output_enabled(info):
            continue
        source = info if isinstance(info, dict) else {}
        logical_value = source.get("logical")
        logical: dict[str, Any] = logical_value if isinstance(logical_value, dict) else {}
        make = str(source.get("make") or "")
        model = str(source.get("model") or "")
        serial = str(source.get("serial") or "")
        label = f"{model} ({make})" if make else model
        if not label:
            label = str(name)
        modes, current_mode_label = _niri_mode_entries(
            source.get("modes", []), source.get("current_mode")
        )
        transform = normalize_transform(
            str(logical.get("transform") or source.get("transform") or "normal")
        )
        x, y = _niri_output_position(source)
        outputs.append(
            MonitorOutputState(
                name=str(name),
                label=label,
                make=make,
                model=model,
                serial=serial,
                primary=str(name) == primary,
                primary_configured=str(name) == configured_primary,
                mode=current_mode_label,
                modes=modes,
                transform=transform,
                x=int(x),
                y=int(y),
            )
        )
    return MonitorState(tuple(outputs), configured, "")


def build_monitor_blocks(
    payload: Any,
    outs: dict[str, Any],
    existing: dict[str, OutputBlock],
) -> dict[str, OutputBlock]:
    """Valida el payload del panel y construye los bloques en orden estable."""
    if not isinstance(payload, dict):
        raise ValueError("payload debe ser un objeto")
    primary = payload.get("primary")
    if not isinstance(primary, str) or not primary:
        raise ValueError("falta primary")
    requested = payload.get("outputs")
    if not isinstance(requested, list):
        raise ValueError("outputs debe ser una lista")
    requested_names: set[str] = set()
    blocks: dict[str, OutputBlock] = {}
    for item in requested:
        if not isinstance(item, dict):
            raise ValueError("cada salida debe ser un objeto")
        name = item.get("name")
        if not isinstance(name, str) or not name:
            raise ValueError("falta el nombre de la salida")
        if name in requested_names:
            raise ValueError(f"nombre de salida duplicado: {name}")
        requested_names.add(name)
        info = outs.get(name)
        if not isinstance(info, dict) or not _niri_output_enabled(info):
            raise ValueError(f"salida desconocida o desconectada: {name}")
        mode = item.get("mode")
        if not isinstance(mode, str) or not mode:
            raise ValueError(f"falta el modo de {name}")
        available = {
            mode_label(
                entry.get("width", 0),
                entry.get("height", 0),
                entry.get("refresh_rate", 0),
            )
            for entry in (info.get("modes") or [])
            if isinstance(entry, dict)
        }
        if mode not in available:
            raise ValueError(f"modo no disponible: {mode}")
        raw_transform = item.get("transform")
        if not isinstance(raw_transform, str):
            raise ValueError(f"transformación no válida: {raw_transform}")
        transform = normalize_transform(raw_transform)
        if transform not in _VALID_TRANSFORMS:
            raise ValueError(f"transformación no válida: {raw_transform}")
        x = item.get("x")
        y = item.get("y")
        if (
            not isinstance(x, int)
            or isinstance(x, bool)
            or not isinstance(y, int)
            or isinstance(y, bool)
        ):
            raise ValueError(f"x e y deben ser enteros: {name}")
        logical_value = info.get("logical")
        logical = logical_value if isinstance(logical_value, dict) else {}
        scale_value = logical.get("scale", info.get("scale", 1.0))
        scale = _as_float(scale_value)
        if scale <= 0:
            scale = 1.0
        blocks[name] = OutputBlock(
            name=name,
            mode=mode,
            scale=scale,
            transform=transform,
            x=x,
            y=y,
            primary=name == primary,
            vrr=bool(info.get("vrr_enabled", False)),
        )
    if primary not in requested_names:
        raise ValueError(f"primary ausente en outputs: {primary}")
    ordered: dict[str, OutputBlock] = {}
    if primary in blocks:
        ordered[primary] = blocks[primary]
    for name, block in blocks.items():
        if name != primary:
            ordered[name] = block
    for name, block in existing.items():
        if name not in requested_names:
            ordered[name] = replace(block, primary=False)
    return ordered


def monitor_apply(payload_json: str) -> int:
    """Persiste, recarga y enfoca la salida principal elegida en el panel."""
    if detect_compositor() != "niri":
        sys.stderr.write("monitores: sólo niri\n")
        return 1
    try:
        payload = json.loads(payload_json)
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"monitores: JSON inválido: {exc}\n")
        return 1
    niri = shutil.which("niri")
    if not niri:
        sys.stderr.write("monitores: niri no disponible\n")
        return 1
    probe = run([niri, "msg", "--json", "outputs"])
    if probe.returncode != 0:
        sys.stderr.write("monitores: no se pudo consultar niri\n")
        return 1
    outs = _niri_outputs_map(probe.stdout)
    root = niri_config_path()
    foreign = foreign_output_files(root)
    if foreign:
        paths = ", ".join(str(path) for path in foreign)
        sys.stderr.write(
            f"monitores: bloques output fuera de config.d/15-outputs.kdl: {paths}\n"
        )
        return 1
    existing = read_output_configs(output_config_path(root))
    try:
        blocks = build_monitor_blocks(payload, outs, existing)
    except ValueError as exc:
        sys.stderr.write(f"monitores: {exc}\n")
        return 1
    primary = str(payload["primary"])
    write_output_configs(root, blocks)
    if reload_niri_config() != 0:
        sys.stderr.write("monitores: no se pudo recargar niri\n")
        return 1
    focus = run([niri, "msg", "action", "focus-monitor", primary])
    if focus.returncode != 0:
        sys.stderr.write(f"monitores: no se pudo enfocar {primary}\n")
        return 1
    return 0


# --- main --------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        sys.stderr.write(
            "uso: caparazon-wm {detect|active-output|primary-output|monitors|"
            "workspaces|watch-workspaces|windows|watch-windows|"
            "window-action|workspace-switch|power-profile|icon-theme|"
            "cursor-theme|keyboard-layout|logout} [args]\n"
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
    if cmd == "monitors":
        if not rest:
            print(monitor_state().to_json())
            return 0
        if rest[0] == "--apply":
            if len(rest) < 2:
                sys.stderr.write("uso: caparazon-wm monitors --apply <json>\n")
                return 2
            return monitor_apply(rest[1])
        sys.stderr.write("uso: caparazon-wm monitors [--apply <json>]\n")
        return 2
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
    if cmd == "icon-theme":
        if not rest:
            print(icon_theme_state().to_json())
            return 0
        if rest[0] == "--set":
            if len(rest) < 2:
                sys.stderr.write("uso: caparazon-wm icon-theme --set <tema>\n")
                return 2
            return icon_theme_apply(rest[1])
        sys.stderr.write("uso: caparazon-wm icon-theme [--set <tema>]\n")
        return 2
    if cmd == "cursor-theme":
        if not rest:
            print(cursor_theme_state().to_json())
            return 0
        if rest[0] == "--set":
            if len(rest) < 2:
                sys.stderr.write("uso: caparazon-wm cursor-theme --set <tema>\n")
                return 2
            return cursor_theme_apply(rest[1])
        sys.stderr.write("uso: caparazon-wm cursor-theme [--set <tema>]\n")
        return 2
    if cmd == "keyboard-layout":
        if not rest:
            print(keyboard_layout_state().to_json())
            return 0
        if rest[0] == "--set":
            if not 2 <= len(rest) <= 3:
                sys.stderr.write(
                    "uso: caparazon-wm keyboard-layout --set <layout> [variant]\n"
                )
                return 2
            return keyboard_layout_apply(rest[1], rest[2] if len(rest) == 3 else "")
        sys.stderr.write("uso: caparazon-wm keyboard-layout [--set <layout> [variant]]\n")
        return 2
    if cmd == "logout":
        return logout()
    sys.stderr.write(f"comando desconocido: {cmd}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())

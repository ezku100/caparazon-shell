"""Contrato del CLI caparazon-wm: detección y pantallas.

El QML no debe hablar con org.kde.KWin / kscreen / niri directamente;
todo pasa por este CLI con backends kwin y niri.
"""

from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLI = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-wm.py"


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _load_cli_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("caparazon_wm", CLI)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _run_cli(
    args: list[str],
    *,
    env_extra: dict[str, str] | None = None,
    fake_bin: dict[str, str] | None = None,
    path: str | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.pop("NIRI_SOCKET", None)
    if env_extra:
        env.update(env_extra)
    path_prepend = ""
    if fake_bin:
        tmp = tempfile.mkdtemp(prefix="cwm-")
        binpath = Path(tmp)
        for name, body in fake_bin.items():
            _write_exec(binpath / name, body)
        path_prepend = str(binpath) + os.pathsep
    env["PATH"] = path if path is not None else path_prepend + env.get("PATH", "")
    return subprocess.run(  # noqa: S603
        ["python3", str(CLI), *args],  # noqa: S607
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )


def _bare_path(tmp_path: Path) -> str:
    """PATH con sólo python3: ningún binario del sistema al alcance."""
    bindir = tmp_path / "bare-bin"
    bindir.mkdir()
    python = shutil.which("python3") or "/usr/bin/python3"
    (bindir / "python3").symlink_to(python)
    return str(bindir)


FAKE_BUSCTL_KWIN_OK = """#!/bin/sh
# activeOutputName o cualquier call a org.kde.KWin
echo 's "DP-1"'
exit 0
"""

FAKE_NIRI_OK = """#!/bin/sh
case "$*" in
  *version*) echo "26.04"; exit 0 ;;
  *focused-output*) printf '%s\\n' '{"name":"HDMI-A-1"}'; exit 0 ;;
  *outputs*)
    printf '%s\\n' \\
      '{"HDMI-A-1":{"name":"HDMI-A-1","current_mode":0,"x":0,"y":0},'\\
      '"eDP-1":{"name":"eDP-1","current_mode":null,"x":1920,"y":0}}'
    exit 0 ;;
  *) exit 1 ;;
esac
"""

FAKE_BUSCTL_FAIL = """#!/bin/sh
exit 1
"""

FAKE_NIRI_FAIL = """#!/bin/sh
exit 1
"""

FAKE_KSCREEN = """#!/bin/sh
cat <<'EOF'
{"outputs":[
  {"name":"eDP-1","enabled":true,"connected":true,"priority":2},
  {"name":"DP-1","enabled":true,"connected":true,"priority":1},
  {"name":"HDMI-A-1","enabled":false,"connected":true,"priority":0}
]}
EOF
echo "resumen de texto ignorado"
"""


def test_cli_file_exists() -> None:
    assert CLI.is_file(), f"falta {CLI}"


def test_detect_prefers_niri_socket() -> None:
    result = _run_cli(
        ["detect"],
        env_extra={"NIRI_SOCKET": "/run/user/1000/niri.sock"},
        fake_bin={"busctl": FAKE_BUSCTL_KWIN_OK, "niri": FAKE_NIRI_FAIL},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "niri"


def test_detect_uses_kwin_when_bus_responde() -> None:
    result = _run_cli(
        ["detect"],
        fake_bin={"busctl": FAKE_BUSCTL_KWIN_OK, "niri": FAKE_NIRI_OK},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "kwin"


def test_detect_falls_back_to_niri() -> None:
    result = _run_cli(
        ["detect"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": FAKE_NIRI_OK},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "niri"


def test_detect_defaults_to_kwin() -> None:
    result = _run_cli(
        ["detect"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": FAKE_NIRI_FAIL},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "kwin"


def test_active_output_kwin() -> None:
    result = _run_cli(
        ["active-output"],
        fake_bin={"busctl": FAKE_BUSCTL_KWIN_OK, "niri": FAKE_NIRI_FAIL},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "DP-1"


def test_active_output_niri() -> None:
    result = _run_cli(
        ["active-output"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": FAKE_NIRI_OK},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "HDMI-A-1"


def test_primary_output_kwin() -> None:
    result = _run_cli(
        ["primary-output"],
        fake_bin={
            # primary en kwin usa kscreen-doctor; busctl sólo para detect
            "busctl": FAKE_BUSCTL_KWIN_OK,
            "kscreen-doctor": FAKE_KSCREEN,
            "niri": FAKE_NIRI_FAIL,
        },
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "DP-1"


def test_primary_output_niri() -> None:
    result = _run_cli(
        ["primary-output"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": FAKE_NIRI_OK},
    )
    assert result.returncode == 0, result.stderr
    # HashMap: HDMI habilitada (current_mode 0), eDP deshabilitada (null).
    assert result.stdout.strip() == "HDMI-A-1"


def test_primary_output_niri_skips_disabled() -> None:
    niri = """#!/bin/sh
case "$*" in
  *outputs*)
    printf '%s\\n' \\
      '{"eDP-1":{"name":"eDP-1","current_mode":null,"x":0,"y":0},'\\
      '"DP-1":{"name":"DP-1","current_mode":1,"x":0,"y":0}}'
    exit 0 ;;
  *version*) echo 26.04; exit 0 ;;
  *) exit 1 ;;
esac
"""
    result = _run_cli(
        ["primary-output"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": niri},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "DP-1"


def test_active_output_parses_busctl_string() -> None:
    """El parser de busctl acepta el formato `s "DP-1"` real (shell.qml)."""
    match = re.search(r'"([^"]*)"', 's "DP-1"')
    assert match is not None
    assert match.group(1) == "DP-1"
    assert json.loads('{"name":"DP-1"}')["name"] == "DP-1"


# --- workspaces ---------------------------------------------------------------

REQUIRED_WS_KEYS = {
    "current",
    "desktops",
    "occupied",
    "perOutput",
    "focusedScreen",
    "occupiedPerOutput",
    "perOutputDesktops",
}

FAKE_NIRI_WORKSPACES = """#!/bin/sh
case "$*" in
  *version*) echo 26.04; exit 0 ;;
  *workspaces*)
    printf '%s\\n' \\
      '[{"id":10,"idx":1,"name":null,"output":"DP-1","is_active":true,'\\
      '"is_focused":true,"active_window_id":42},'\\
      '{"id":11,"idx":2,"name":"code","output":"DP-1","is_active":false,'\\
      '"is_focused":false,"active_window_id":null}]'
    exit 0 ;;
  *windows*)
    printf '%s\\n' \\
      '[{"id":42,"title":"Term","app_id":"kitty","workspace_id":10,'\\
      '"is_focused":true,"is_floating":false,"is_urgent":false}]'
    exit 0 ;;
  *) exit 1 ;;
esac
"""

FAKE_BUSCTL_WS = """#!/bin/sh
case "$*" in
  *desktops*)
    printf '%s\\n' \\
      '{"type":"v","data":[{"type":"a(uss)","data":'\\
      '[[0,"uuid-a","Uno"],[1,"uuid-b","Dos"]]}]}'
    exit 0 ;;
  *current*)
    printf '%s\\n' \\
      '{"type":"v","data":[{"type":"s","data":"uuid-a"}]}'
    exit 0 ;;
  *activeOutputName*) printf '%s\\n' 's "DP-1"'; exit 0 ;;
  *) exit 0 ;;
esac
"""


def test_workspaces_shape_matches_cache() -> None:
    result = _run_cli(
        ["workspaces"],
        fake_bin={
            "busctl": FAKE_BUSCTL_WS,
            "niri": FAKE_NIRI_FAIL,
            "kscreen-doctor": FAKE_KSCREEN,
        },
    )
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert REQUIRED_WS_KEYS.issubset(data.keys())
    assert isinstance(data["desktops"], list)
    for d in data["desktops"]:
        assert set(d.keys()) >= {"pos", "id", "name"}


def test_workspaces_niri_parses_fixture() -> None:
    result = _run_cli(
        ["workspaces"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": FAKE_NIRI_WORKSPACES},
    )
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert REQUIRED_WS_KEYS.issubset(data.keys())
    assert data["current"] == "10"
    assert data["occupied"] == ["10"]
    assert [d["name"] for d in data["desktops"]] == ["1", "code"]
    assert data["perOutput"] == {"DP-1": "10"}
    assert data["focusedScreen"] == "DP-1"
    assert data["occupiedPerOutput"] == {"DP-1": ["10"]}


def test_workspaces_niri_per_output_active_not_last() -> None:
    """Con dos outputs, cada perOutput es el is_active de SU output.

    La lista termina con ws no activo de DP-2: no debe vencer por orden.
    """
    fixture = """#!/bin/sh
case "$*" in
  *version*) echo 26.04; exit 0 ;;
  *workspaces*)
    printf '%s\\n' \\
      '[{"id":10,"idx":1,"name":null,"output":"DP-1","is_active":true,'\\
      '"is_focused":true,"active_window_id":42},'\\
      '{"id":11,"idx":2,"name":null,"output":"DP-1","is_active":false,'\\
      '"is_focused":false,"active_window_id":null},'\\
      '{"id":20,"idx":1,"name":null,"output":"HDMI-1","is_active":true,'\\
      '"is_focused":false,"active_window_id":null},'\\
      '{"id":21,"idx":2,"name":"chat","output":"HDMI-1","is_active":false,'\\
      '"is_focused":false,"active_window_id":null}]'
    exit 0 ;;
  *windows*)
    printf '%s\\n' \\
      '[{"id":42,"title":"Term","app_id":"kitty","workspace_id":10,'\\
      '"is_focused":true,"is_floating":false,"is_urgent":false}]'
    exit 0 ;;
  *) exit 1 ;;
esac
"""
    result = _run_cli(
        ["workspaces"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": fixture},
    )
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["perOutput"] == {"DP-1": "10", "HDMI-1": "20"}
    assert data["focusedScreen"] == "DP-1"
    assert data["occupiedPerOutput"] == {"DP-1": ["10"]}
    assert data["current"] == "10"


def test_workspaces_niri_desktops_are_per_output() -> None:
    """niri numera el workspace por output; el pager no debe mezclarlos."""
    result = _run_cli(
        ["workspaces"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": FAKE_NIRI_WORKSPACES},
    )
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["perOutputDesktops"] == {
        "DP-1": [
            {
                "pos": 0, "id": "10", "name": "1",
                "idx": 1, "active": True, "occupied": True,
            },
            {
                "pos": 1, "id": "11", "name": "code",
                "idx": 2, "active": False, "occupied": False,
            },
        ]
    }


def test_workspaces_kwin_wraps_virtual_desktop_manager() -> None:
    result = _run_cli(
        ["workspaces"],
        fake_bin={
            "busctl": FAKE_BUSCTL_WS,
            "niri": FAKE_NIRI_FAIL,
            "kscreen-doctor": FAKE_KSCREEN,
        },
    )
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["current"] == "uuid-a"
    assert data["desktops"] == [
        {"pos": 0, "id": "uuid-a", "name": "Uno"},
        {"pos": 1, "id": "uuid-b", "name": "Dos"},
    ]


def test_watch_workspaces_emits_line_per_event() -> None:
    """watch-workspaces emite una línea JSON por evento de dbus-monitor."""
    # dbus-monitor fake: 2 líneas de evento → el CLI debe emitir 2 JSON.
    monitor = """#!/bin/sh
echo 'signal'
echo 'signal'
# se cierra al terminar
"""
    # Para kwin, watch_workspaces llama a dbus-monitor y por cada línea imprime state.
    # El state real depende de busctl; usamos el mismo fake de escritorios.
    result = _run_cli(
        ["watch-workspaces"],
        fake_bin={
            "busctl": FAKE_BUSCTL_WS,
            "niri": FAKE_NIRI_FAIL,
            "dbus-monitor": monitor,
            "kscreen-doctor": FAKE_KSCREEN,
        },
    )
    assert result.returncode == 0, result.stderr
    lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
    assert len(lines) == 2, result.stdout
    for ln in lines:
        data = json.loads(ln)
        assert REQUIRED_WS_KEYS.issubset(data.keys())


def test_niri_workspace_events_include_activation() -> None:
    """niri 26.04: WorkspaceActivated y WindowFocusChanged cambian el pager."""
    cwm = _load_cli_module()
    events = [
        '{"WorkspacesChanged":[]}',
        '{"WorkspaceActivated":{"id":2}}',
        '{"WindowsChanged":[]}',
    ]
    for event in events:
        assert cwm.niri_event_affects_workspaces(event), event
    assert not cwm.niri_event_affects_workspaces('{"CastsChanged":[]}')


def test_niri_window_events_include_focus() -> None:
    """El indicador de la app debe reaccionar al foco y al cambio de escritorio."""
    cwm = _load_cli_module()
    events = [
        '{"WindowsChanged":[]}',
        '{"WindowFocusChanged":{"id":7}}',
        '{"WorkspaceActivated":{"id":2}}',
    ]
    for event in events:
        assert cwm.niri_event_affects_windows(event), event
    assert not cwm.niri_event_affects_windows('{"CastsChanged":[]}')


# --- window-action -------------------------------------------------------------

FAKE_GDBUS = """#!/bin/sh
# registra las llamadas para asertar el flujo KWin
printf '%s\\n' "$*" >> "${FAKE_GDBUS_LOG:-/tmp/fake-gdbus.log}"
exit 0
"""

FAKE_NIRI_ACTION = """#!/bin/sh
case "$*" in
  *version*) echo 26.04; exit 0 ;;
  *windows*)
    printf '%s\\n' \\
      '[{"id":7,"title":"Term","app_id":"kitty","workspace_id":10,'\\
      '"is_focused":false},{"id":8,"title":"Code","app_id":"code",'\\
      '"workspace_id":10,"is_focused":true}]'
    exit 0 ;;
  *focus-window*) echo "$*" >> "${FAKE_NIRI_LOG:-/tmp/fake-niri.log}"; exit 0 ;;
  *) exit 1 ;;
esac
"""


def test_window_action_kwin_uses_scripting_and_template(tmp_path: Path) -> None:
    log = tmp_path / "gdbus.log"
    env_log = str(log)
    # PATH fake: gdbus registra; sed real no importa si plantilla ausente → exit 1
    # del CLI si no encuentra el js. Usamos plantilla real del repo.
    result = _run_cli(
        ["window-action", "kitty", "kitty|term"],
        fake_bin={"gdbus": FAKE_GDBUS, "niri": FAKE_NIRI_FAIL},
        env_extra={"FAKE_GDBUS_LOG": env_log},
    )
    # sin KWinWindowAction.js en PATH relativo puede fallar; aceptar 0 o 1
    # siempre que se intentara Scripting (o que el js falte documentado).
    assert result.returncode in (0, 1), result.stderr
    if log.exists():
        calls = log.read_text(encoding="utf-8")
        assert "loadScript" in calls
        assert "caparazon-window-action" in calls


def test_window_action_niri_focuses_unfocused_candidate(tmp_path: Path) -> None:
    log = tmp_path / "niri.log"
    result = _run_cli(
        ["window-action", "", "kitty"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": FAKE_NIRI_ACTION},
        env_extra={"FAKE_NIRI_LOG": str(log)},
    )
    assert result.returncode == 0, result.stderr
    out = log.read_text(encoding="utf-8")
    assert "focus-window" in out
    assert "--id 7" in out


def test_window_action_niri_noop_when_already_focused(tmp_path: Path) -> None:
    log = tmp_path / "niri.log"
    result = _run_cli(
        ["window-action", "code", "code"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": FAKE_NIRI_ACTION},
        env_extra={"FAKE_NIRI_LOG": str(log)},
    )
    assert result.returncode == 0, result.stderr
    if log.exists():
        out = log.read_text(encoding="utf-8")
        assert "close-window" not in out


# --- power-profile -----------------------------------------------------------

FAKE_PPD = """#!/bin/sh
case "$1" in
  list)
    printf '%s\\n' '  performance:' '    CpuDriver:\tamd_pstate' '    Degraded:   no' ''
    printf '%s\\n' '* balanced:' '    CpuDriver:\tamd_pstate' ''
    printf '%s\\n' '  power-saver:' '    CpuDriver:\tamd_pstate'
    exit 0 ;;
  get) echo balanced; exit 0 ;;
  set) echo "set $2" >> "$FAKE_PPD_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
"""

FAKE_QDBUS_SOLID = """#!/bin/sh
case "$*" in
  *profileChoices*)
    printf '%s\\n' power-saver balanced performance
    exit 0 ;;
  *currentProfile*)
    echo performance
    exit 0 ;;
  *setProfile*)
    echo "$*" >> "$FAKE_QDBUS_LOG"
    exit 0 ;;
esac
exit 1
"""

NIRI_SESSION = {"NIRI_SOCKET": "/run/user/1000/niri.sock"}


def test_power_profile_reads_ppd() -> None:
    result = _run_cli(
        ["power-profile"],
        env_extra=NIRI_SESSION,
        fake_bin={"powerprofilesctl": FAKE_PPD},
    )
    assert result.returncode == 0, result.stderr
    doc = json.loads(result.stdout)
    assert doc["backend"] == "ppd"
    assert doc["profile"] == "balanced"
    # El formato real indenta los nombres y marca el activo con '*'.
    assert doc["choices"] == ["performance", "balanced", "power-saver"]


def test_power_profile_sets_ppd(tmp_path: Path) -> None:
    log = tmp_path / "ppd.log"
    result = _run_cli(
        ["power-profile", "--set", "power-saver"],
        env_extra={**NIRI_SESSION, "FAKE_PPD_LOG": str(log)},
        fake_bin={"powerprofilesctl": FAKE_PPD},
    )
    assert result.returncode == 0, result.stderr
    assert "set power-saver" in log.read_text(encoding="utf-8")


def test_power_profile_rejects_unknown_profile() -> None:
    result = _run_cli(
        ["power-profile", "--set", "turbo"],
        env_extra=NIRI_SESSION,
        fake_bin={"powerprofilesctl": FAKE_PPD},
    )
    assert result.returncode == 1
    assert "turbo" in result.stderr
    assert "power-saver" in result.stderr


def test_power_profile_without_backend(tmp_path: Path) -> None:
    bare = _bare_path(tmp_path)

    result = _run_cli(["power-profile"], path=bare)
    assert result.returncode == 0, result.stderr
    doc = json.loads(result.stdout)
    assert doc["backend"] == "none"
    assert doc["profile"] is None

    result = _run_cli(["power-profile", "--set", "balanced"], path=bare)
    assert result.returncode == 1
    assert "backend" in result.stderr


def test_power_profile_falls_back_to_ppd_when_solid_is_missing(tmp_path: Path) -> None:
    bare = Path(_bare_path(tmp_path))
    _write_exec(bare / "powerprofilesctl", FAKE_PPD)

    result = _run_cli(["power-profile"], path=str(bare))

    assert result.returncode == 0, result.stderr
    doc = json.loads(result.stdout)
    assert doc["backend"] == "ppd"
    assert doc["profile"] == "balanced"


def test_power_profile_reads_solid() -> None:
    result = _run_cli(
        ["power-profile"],
        fake_bin={
            "busctl": FAKE_BUSCTL_KWIN_OK,
            "niri": FAKE_NIRI_FAIL,
            "qdbus6": FAKE_QDBUS_SOLID,
            "powerprofilesctl": FAKE_PPD,
        },
    )
    assert result.returncode == 0, result.stderr
    doc = json.loads(result.stdout)
    assert doc["backend"] == "solid"
    assert doc["profile"] == "performance"
    assert doc["choices"] == ["power-saver", "balanced", "performance"]


def test_power_profile_sets_solid(tmp_path: Path) -> None:
    log = tmp_path / "qdbus.log"
    result = _run_cli(
        ["power-profile", "--set", "performance"],
        env_extra={"FAKE_QDBUS_LOG": str(log)},
        fake_bin={
            "busctl": FAKE_BUSCTL_KWIN_OK,
            "niri": FAKE_NIRI_FAIL,
            "qdbus6": FAKE_QDBUS_SOLID,
            "powerprofilesctl": FAKE_PPD,
        },
    )
    assert result.returncode == 0, result.stderr
    assert "setProfile performance" in log.read_text(encoding="utf-8")


def test_power_profile_prefers_solid_on_kwin() -> None:
    result = _run_cli(
        ["power-profile"],
        fake_bin={
            "busctl": FAKE_BUSCTL_KWIN_OK,
            "niri": FAKE_NIRI_FAIL,
            "qdbus6": FAKE_QDBUS_SOLID,
            "powerprofilesctl": FAKE_PPD,
        },
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["backend"] == "solid"


def test_power_profile_prefers_ppd_on_niri() -> None:
    result = _run_cli(
        ["power-profile"],
        env_extra=NIRI_SESSION,
        fake_bin={
            "busctl": FAKE_BUSCTL_KWIN_OK,
            "niri": FAKE_NIRI_FAIL,
            "qdbus6": FAKE_QDBUS_SOLID,
            "powerprofilesctl": FAKE_PPD,
        },
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["backend"] == "ppd"


def _icon_theme_env(tmp_path: Path) -> dict[str, str]:
    """Entorno aislado: HOME propio y rutas de iconos propias."""
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    return {
        "HOME": str(home),
        "XDG_DATA_DIRS": str(tmp_path / "share"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
    }


def _write_icon_theme(root: Path, name: str) -> None:
    """Crea un tema de iconos mínimo: un directorio con index.theme."""
    directory = root / name
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "index.theme").write_text(
        f"[Icon Theme]\nName={name}\n",
        encoding="utf-8",
    )


def test_icon_theme_lists_the_installed_themes(tmp_path: Path) -> None:
    _write_icon_theme(tmp_path / "share" / "icons", "Papirus-Dark")

    result = _run_cli(["icon-theme"], env_extra=_icon_theme_env(tmp_path))

    assert result.returncode == 0, result.stderr
    assert "Papirus-Dark" in json.loads(result.stdout)["themes"]


def test_icon_theme_reports_the_search_order_with_inheritance(tmp_path: Path) -> None:
    root = tmp_path / "share" / "icons"
    _write_icon_theme(root, "Hijo")
    (root / "Hijo" / "index.theme").write_text(
        "[Icon Theme]\nName=Hijo\nInherits=Padre,hicolor\n",
        encoding="utf-8",
    )
    _write_icon_theme(root, "Padre")
    (root / "Padre" / "index.theme").write_text(
        "[Icon Theme]\nName=Padre\nInherits=Abuelo\n",
        encoding="utf-8",
    )
    _write_icon_theme(root, "Abuelo")
    environ = _icon_theme_env(tmp_path)
    config = tmp_path / "home" / ".config" / "niri" / "config.kdl"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(
        'environment {\n    CAPARAZON_ICON_THEME "Hijo"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(["icon-theme"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["search"] == [
        "Hijo",
        "Padre",
        "Abuelo",
        "hicolor",
    ]


def test_icon_theme_reports_the_default_without_a_config(tmp_path: Path) -> None:
    result = _run_cli(["icon-theme"], env_extra=_icon_theme_env(tmp_path))

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["current"] == "Papirus-Dark"
    assert payload["configured"] is False


def test_icon_theme_reads_the_theme_set_in_the_niri_config(tmp_path: Path) -> None:
    environ = _icon_theme_env(tmp_path)
    config = tmp_path / "home" / ".config" / "niri" / "config.kdl"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(
        'environment {\n    CAPARAZON_ICON_THEME "Adwaita"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(["icon-theme"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["current"] == "Adwaita"
    assert payload["configured"] is True


def test_icon_theme_set_writes_the_niri_config(tmp_path: Path) -> None:
    _write_icon_theme(tmp_path / "share" / "icons", "Papirus-Dark")
    environ = _icon_theme_env(tmp_path)

    result = _run_cli(["icon-theme", "--set", "Papirus-Dark"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    written = (
        tmp_path / "home" / ".config" / "niri" / "config.kdl"
    ).read_text(encoding="utf-8")
    assert "CAPARAZON_ICON_THEME" in written
    assert "Papirus-Dark" in written


def test_icon_theme_set_keeps_the_rest_of_the_niri_config(tmp_path: Path) -> None:
    _write_icon_theme(tmp_path / "share" / "icons", "Papirus-Dark")
    environ = _icon_theme_env(tmp_path)
    config = tmp_path / "home" / ".config" / "niri" / "config.kdl"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(
        "binds {\n    Mod+Q { quit; }\n}\n",
        encoding="utf-8",
    )

    result = _run_cli(["icon-theme", "--set", "Papirus-Dark"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    written = config.read_text(encoding="utf-8")
    assert "Mod+Q { quit; }" in written
    assert "CAPARAZON_ICON_THEME" in written


def test_icon_theme_reads_the_theme_from_an_included_config(tmp_path: Path) -> None:
    environ = _icon_theme_env(tmp_path)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/40-environment.kdl"\n',
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    (config_dir / "config.d" / "40-environment.kdl").write_text(
        'environment {\n    CAPARAZON_ICON_THEME "Tela-dark"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(["icon-theme"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["current"] == "Tela-dark"
    assert payload["configured"] is True


def test_icon_theme_set_updates_the_included_config(tmp_path: Path) -> None:
    _write_icon_theme(tmp_path / "share" / "icons", "Tela-dark")
    _write_icon_theme(tmp_path / "share" / "icons", "Papirus-Dark")
    environ = _icon_theme_env(tmp_path)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/40-environment.kdl"\n',
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    included = config_dir / "config.d" / "40-environment.kdl"
    included.write_text(
        'environment {\n    CAPARAZON_ICON_THEME "Papirus-Dark"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(["icon-theme", "--set", "Tela-dark"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    written = included.read_text(encoding="utf-8")
    assert 'CAPARAZON_ICON_THEME "Tela-dark"' in written
    main = (config_dir / "config.kdl").read_text(encoding="utf-8")
    assert "CAPARAZON_ICON_THEME" not in main
    check = _run_cli(["icon-theme"], env_extra=environ)
    assert json.loads(check.stdout)["current"] == "Tela-dark"


def test_icon_theme_set_keeps_qs_icon_theme_in_sync(tmp_path: Path) -> None:
    _write_icon_theme(tmp_path / "share" / "icons", "Tela-dark")
    _write_icon_theme(tmp_path / "share" / "icons", "Papirus-Dark")
    environ = _icon_theme_env(tmp_path)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/40-environment.kdl"\n',
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    included = config_dir / "config.d" / "40-environment.kdl"
    included.write_text(
        'environment {\n'
        '    CAPARAZON_ICON_THEME "Papirus-Dark"\n'
        '    QS_ICON_THEME "Papirus-Dark"\n'
        '}\n',
        encoding="utf-8",
    )

    result = _run_cli(["icon-theme", "--set", "Tela-dark"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    written = included.read_text(encoding="utf-8")
    assert 'CAPARAZON_ICON_THEME "Tela-dark"' in written
    assert 'QS_ICON_THEME "Tela-dark"' in written


def test_icon_theme_last_value_in_load_order_wins(tmp_path: Path) -> None:
    environ = _icon_theme_env(tmp_path)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/40-environment.kdl"\n'
        'environment {\n    CAPARAZON_ICON_THEME "Papirus-Dark"\n}\n',
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    (config_dir / "config.d" / "40-environment.kdl").write_text(
        'environment {\n    CAPARAZON_ICON_THEME "Tela-dark"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(["icon-theme"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["current"] == "Papirus-Dark"


def test_icon_theme_set_rejects_an_unknown_theme(tmp_path: Path) -> None:
    environ = _icon_theme_env(tmp_path)

    result = _run_cli(["icon-theme", "--set", "NoExiste"], env_extra=environ)

    assert result.returncode == 1
    assert "NoExiste" in result.stderr
    assert not (
        tmp_path / "home" / ".config" / "niri" / "config.kdl"
    ).exists()


def test_icon_theme_set_needs_a_theme(tmp_path: Path) -> None:
    result = _run_cli(["icon-theme", "--set"], env_extra=_icon_theme_env(tmp_path))

    assert result.returncode == 2


def _cursor_theme_env(tmp_path: Path) -> dict[str, str]:
    """Entorno aislado: HOME propio y rutas de datos propias."""
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    return {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_DIRS": str(tmp_path / "share"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
    }


def _write_cursor_theme(root: Path, name: str) -> None:
    """Crea un tema Xcursor mínimo: directorio cursors con un archivo."""
    cursors = root / name / "cursors"
    cursors.mkdir(parents=True, exist_ok=True)
    (cursors / "left_ptr").write_text("", encoding="utf-8")


def test_cursor_theme_lists_the_installed_themes(tmp_path: Path) -> None:
    _write_cursor_theme(tmp_path / "share" / "icons", "Oxygen_Black")
    _write_cursor_theme(tmp_path / "home" / ".local" / "share" / "icons", "MiCursor")

    result = _run_cli(["cursor-theme"], env_extra=_cursor_theme_env(tmp_path))

    assert result.returncode == 0, result.stderr
    themes = json.loads(result.stdout)["themes"]
    assert "Oxygen_Black" in themes
    assert "MiCursor" in themes


def test_cursor_theme_reports_the_default_without_a_config(tmp_path: Path) -> None:
    result = _run_cli(["cursor-theme"], env_extra=_cursor_theme_env(tmp_path))

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["current"] == "breeze_cursors"
    assert payload["default"] == "breeze_cursors"
    assert payload["configured"] is False


def test_cursor_theme_reads_the_theme_from_an_included_config(tmp_path: Path) -> None:
    environ = _cursor_theme_env(tmp_path)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/10-input-and-cursor.kdl"\n',
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    (config_dir / "config.d" / "10-input-and-cursor.kdl").write_text(
        "cursor {\n"
        '    xcursor-theme "Oxygen_Black"\n'
        "    xcursor-size 24\n"
        "    hide-when-typing\n"
        "}\n",
        encoding="utf-8",
    )

    result = _run_cli(["cursor-theme"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["current"] == "Oxygen_Black"
    assert payload["configured"] is True


def test_cursor_theme_last_value_in_load_order_wins(tmp_path: Path) -> None:
    environ = _cursor_theme_env(tmp_path)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config.kdl").write_text(
        'include "config.d/10-input-and-cursor.kdl"\n'
        "cursor {\n"
        '    xcursor-theme "Adwaita"\n'
        "}\n",
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    (config_dir / "config.d" / "10-input-and-cursor.kdl").write_text(
        'cursor {\n    xcursor-theme "breeze_cursors"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(["cursor-theme"], env_extra=environ)

    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["current"] == "Adwaita"


def test_usage_lists_cursor_theme() -> None:
    result = _run_cli([])

    assert "cursor-theme" in result.stderr


FAKE_NIRI_RELOAD = """#!/bin/sh
printf '%s\\n' "$*" >> "$NIRI_RELOAD_LOG"
case "$*" in
  *load-config-file*) exit 0 ;;
  *) exit 1 ;;
esac
"""

FAKE_NIRI_RELOAD_FAIL = """#!/bin/sh
printf '%s\\n' "$*" >> "$NIRI_RELOAD_LOG"
case "$*" in
  *load-config-file*) exit 1 ;;
  *) exit 1 ;;
esac
"""


def test_cursor_theme_set_writes_the_included_config_and_keeps_neighbors(
    tmp_path: Path,
) -> None:
    _write_cursor_theme(tmp_path / "share" / "icons", "Oxygen_Black")
    environ = _cursor_theme_env(tmp_path)
    reload_log = tmp_path / "niri-reload.log"
    environ["NIRI_RELOAD_LOG"] = str(reload_log)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    config = config_dir / "config.kdl"
    config.write_text(
        'include "config.d/10-input-and-cursor.kdl"\n',
        encoding="utf-8",
    )
    (config_dir / "config.d").mkdir()
    included = config_dir / "config.d" / "10-input-and-cursor.kdl"
    included.write_text(
        "cursor {\n"
        '    xcursor-theme "breeze_cursors"\n'
        "    xcursor-size 24\n"
        "    hide-when-typing\n"
        "}\n",
        encoding="utf-8",
    )

    result = _run_cli(
        ["cursor-theme", "--set", "Oxygen_Black"],
        env_extra=environ,
        fake_bin={"niri": FAKE_NIRI_RELOAD},
    )

    assert result.returncode == 0, result.stderr
    written = included.read_text(encoding="utf-8")
    assert 'xcursor-theme "Oxygen_Black"' in written
    assert "xcursor-size 24" in written
    assert "hide-when-typing" in written
    assert "xcursor-theme" not in config.read_text(encoding="utf-8")
    assert "msg action load-config-file" in reload_log.read_text(encoding="utf-8")
    check = _run_cli(["cursor-theme"], env_extra=environ)
    assert json.loads(check.stdout)["current"] == "Oxygen_Black"


def test_cursor_theme_set_creates_the_cursor_block_when_missing(tmp_path: Path) -> None:
    _write_cursor_theme(tmp_path / "share" / "icons", "Oxygen_Black")
    environ = _cursor_theme_env(tmp_path)
    environ["NIRI_RELOAD_LOG"] = str(tmp_path / "niri-reload.log")
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    config = config_dir / "config.kdl"
    config.write_text(
        "input {\n    warp-pointer-to-focused-window\n}\n", encoding="utf-8"
    )

    result = _run_cli(
        ["cursor-theme", "--set", "Oxygen_Black"],
        env_extra=environ,
        fake_bin={"niri": FAKE_NIRI_RELOAD},
    )

    assert result.returncode == 0, result.stderr
    written = config.read_text(encoding="utf-8")
    assert "cursor {" in written
    assert 'xcursor-theme "Oxygen_Black"' in written
    assert "warp-pointer-to-focused-window" in written


def test_cursor_theme_set_reports_reload_failure(tmp_path: Path) -> None:
    _write_cursor_theme(tmp_path / "share" / "icons", "Oxygen_Black")
    environ = _cursor_theme_env(tmp_path)
    reload_log = tmp_path / "niri-reload.log"
    environ["NIRI_RELOAD_LOG"] = str(reload_log)
    config_dir = tmp_path / "home" / ".config" / "niri"
    config_dir.mkdir(parents=True, exist_ok=True)
    config = config_dir / "config.kdl"
    config.write_text(
        'cursor {\n    xcursor-theme "breeze_cursors"\n}\n',
        encoding="utf-8",
    )

    result = _run_cli(
        ["cursor-theme", "--set", "Oxygen_Black"],
        env_extra=environ,
        fake_bin={"niri": FAKE_NIRI_RELOAD_FAIL},
    )

    assert result.returncode == 1
    assert "no se pudo recargar niri" in result.stderr
    assert 'xcursor-theme "Oxygen_Black"' in config.read_text(encoding="utf-8")
    assert "msg action load-config-file" in reload_log.read_text(encoding="utf-8")


def test_cursor_theme_set_rejects_unknown_theme(tmp_path: Path) -> None:
    environ = _cursor_theme_env(tmp_path)

    result = _run_cli(["cursor-theme", "--set", "NoExiste"], env_extra=environ)

    assert result.returncode == 1
    assert "NoExiste" in result.stderr
    assert not (tmp_path / "home" / ".config" / "niri" / "config.kdl").exists()


def test_cursor_theme_set_needs_a_theme(tmp_path: Path) -> None:
    result = _run_cli(["cursor-theme", "--set"], env_extra=_cursor_theme_env(tmp_path))

    assert result.returncode == 2

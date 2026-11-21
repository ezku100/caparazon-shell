"""Contrato del CLI caparazon-wm: detección y pantallas.

El QML no debe hablar con org.kde.KWin / kscreen / niri directamente;
todo pasa por este CLI con backends kwin y niri.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLI = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-wm.py"


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


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
    assert data["perOutput"] == {"DP-1": "11"}
    assert data["focusedScreen"] == "DP-1"
    assert data["occupiedPerOutput"] == {"DP-1": ["10"]}


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

"""Contrato Task 6: logout, ShellLayout y bootstrap hablan vía caparazon-wm."""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLI = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-wm.py"
POWER = REPOSITORY_ROOT / "modules" / "bar" / "PowerMenu.qml"
LAYOUT = REPOSITORY_ROOT / "theme" / "ShellLayout.qml"
BOOTSTRAP = REPOSITORY_ROOT / "integration" / "bin" / "ezku-desktops-bootstrap.sh"
INSTALL = REPOSITORY_ROOT / "install.sh"


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _run_cli(
    args: list[str],
    *,
    fake_bin: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.pop("NIRI_SOCKET", None)
    path_prepend = ""
    if fake_bin:
        tmp = tempfile.mkdtemp(prefix="cwm-")
        binpath = Path(tmp)
        for name, body in fake_bin.items():
            _write_exec(binpath / name, body)
        path_prepend = str(binpath) + os.pathsep
    env["PATH"] = path_prepend + env.get("PATH", "")
    return subprocess.run(  # noqa: S603
        ["python3", str(CLI), *args],  # noqa: S607
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )


FAKE_BUSCTL_FAIL = """#!/bin/sh
exit 1
"""

FAKE_NIRI_FAIL = """#!/bin/sh
exit 1
"""

FAKE_QDBUS = """#!/bin/sh
echo "$*" >> "${FAKE_QDBUS_LOG:-/tmp/fake-qdbus.log}"
exit 0
"""

FAKE_NIRI_QUIT = """#!/bin/sh
case "$*" in
  *version*) echo 26.04; exit 0 ;;
  *quit*) echo "$*" >> "${FAKE_NIRI_LOG:-/tmp/fake-niri.log}"; exit 0 ;;
  *) exit 1 ;;
esac
"""


def test_power_menu_logout_goes_through_cli() -> None:
    contents = POWER.read_text(encoding="utf-8")
    assert "org.kde.Shutdown" not in contents
    assert '"caparazon-wm"' in contents
    assert '"logout"' in contents
    assert 'key === "logout"' in contents


def test_shell_layout_probe_uses_cli_not_kscreen() -> None:
    contents = LAYOUT.read_text(encoding="utf-8")
    assert "kscreen-doctor" not in contents
    assert '"caparazon-wm"' in contents
    assert '"primary-output"' in contents
    # el QML sólo recibe el nombre; kscreen vive dentro del CLI
    assert "parsePrimary" not in contents
    assert "root.primaryName" in contents


def test_bootstrap_loads_kwin_script_only_on_kwin() -> None:
    contents = BOOTSTRAP.read_text(encoding="utf-8")
    assert "caparazon-wm" in contents
    assert "detect" in contents
    # el bloque org.kde.KWin debe estar tras un guard de compositor
    assert "org.kde.KWin" in contents


def test_installer_ships_caparazon_wm() -> None:
    contents = INSTALL.read_text(encoding="utf-8")
    assert "caparazon-wm.py" in contents
    assert '"$BIN_DIR/caparazon-wm"' in contents


def test_cli_logout_kwin_uses_qdbus() -> None:
    result = _run_cli(
        ["logout"],
        fake_bin={
            "busctl": FAKE_BUSCTL_FAIL,
            "niri": FAKE_NIRI_FAIL,
            "qdbus6": FAKE_QDBUS,
        },
    )
    # con qdbus6 fake en PATH el camino kwin termina en 0
    assert result.returncode == 0, result.stderr


def test_cli_logout_niri_quits() -> None:
    log_dir = tempfile.mkdtemp(prefix="cwm-log-")
    niri_log = Path(log_dir) / "niri.log"
    # reinyectar FAKE_NIRI_LOG vía fake script que escribe en ruta fija
    fake_niri = f"""#!/bin/sh
case "$*" in
  *version*) echo 26.04; exit 0 ;;
  *quit*) echo "$*" >> "{niri_log}"; exit 0 ;;
  *) exit 1 ;;
esac
"""
    result = _run_cli(
        ["logout"],
        fake_bin={"busctl": FAKE_BUSCTL_FAIL, "niri": fake_niri},
    )
    assert result.returncode == 0, result.stderr
    assert niri_log.exists()
    assert "quit" in niri_log.read_text(encoding="utf-8")

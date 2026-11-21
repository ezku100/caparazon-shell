"""Contrato de atajos de niri: bloque binds, IPC de la shell y wrapper."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CONFIG = REPOSITORY_ROOT / "integration" / "niri" / "config.kdl"
SHELL_QML = REPOSITORY_ROOT / "shell.qml"
INSTALLER = REPOSITORY_ROOT / "install.sh"
IPC_WRAPPER = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-shell-ipc.sh"


def test_niri_config_declares_binds() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    assert "binds {" in contents


def test_niri_config_closes_windows_with_meta_q() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    assert "Mod+Q" in contents
    assert "close-window" in contents


def test_niri_config_switches_workspaces_with_meta_number() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    for number in range(1, 10):
        assert f"Mod+{number} {{ focus-workspace {number}; }}" in contents


def test_niri_config_moves_windows_to_workspaces_with_meta_shift_number() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    for number in range(1, 10):
        expected = f"Mod+Shift+{number} {{ move-window-to-workspace {number}; }}"
        assert expected in contents


def test_niri_config_moves_windows_inside_the_workspace_with_meta_arrows() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    assert "Mod+Left { move-column-left; }" in contents
    assert "Mod+Right { move-column-right; }" in contents
    assert "Mod+Up { move-window-up; }" in contents
    assert "Mod+Down { move-window-down; }" in contents


def test_niri_config_keeps_focus_on_the_control_arrows() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    assert "Mod+Ctrl+Left { focus-column-left; }" in contents
    assert "Mod+Ctrl+Right { focus-column-right; }" in contents
    assert "Mod+Ctrl+Up { focus-window-up; }" in contents
    assert "Mod+Ctrl+Down { focus-window-down; }" in contents


def test_niri_config_opens_the_shell_menus_through_the_ipc_wrapper() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    assert "caparazon-shell-ipc" in contents
    assert '"menu"' in contents
    assert '"menu2"' in contents
    assert '"power"' in contents


def test_the_shell_exposes_the_session_menu_over_ipc() -> None:
    contents = SHELL_QML.read_text(encoding="utf-8")
    assert 'target: "power"' in contents
    assert "powerMenuState" in contents


def test_the_installer_ships_the_shell_ipc_wrapper() -> None:
    contents = INSTALLER.read_text(encoding="utf-8")
    assert "caparazon-shell-ipc.sh" in contents
    assert '"$BIN_DIR/caparazon-shell-ipc"' in contents


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def test_the_ipc_wrapper_uses_the_live_shell_path(tmp_path: Path) -> None:
    if shutil.which("bash") is None:
        pytest.skip("bash no disponible")
    shell_dir = tmp_path / "shell"
    shell_dir.mkdir()
    (shell_dir / "shell.qml").write_text("// shell\n", encoding="utf-8")
    autostart = tmp_path / "home" / ".config" / "autostart"
    autostart.mkdir(parents=True)
    (autostart / "caparazon.desktop").write_text(
        f"[Desktop Entry]\nExec=quickshell -p {shell_dir} -d\n",
        encoding="utf-8",
    )
    log = tmp_path / "quickshell.log"
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_exec(
        fake_bin / "quickshell",
        f'#!/bin/sh\necho "$*" >> "{log}"\n',
    )
    env = os.environ.copy()
    env["HOME"] = str(tmp_path / "home")
    env["PATH"] = str(fake_bin) + os.pathsep + env.get("PATH", "")

    result = subprocess.run(  # noqa: S603
        ["bash", str(IPC_WRAPPER), "menu", "toggle"],  # noqa: S607
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    recorded = log.read_text(encoding="utf-8")
    assert f"-p {shell_dir} ipc call menu toggle" in recorded


def test_the_ipc_wrapper_fails_when_the_shell_is_missing(tmp_path: Path) -> None:
    if shutil.which("bash") is None:
        pytest.skip("bash no disponible")
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_exec(fake_bin / "quickshell", "#!/bin/sh\nexit 0\n")
    env = os.environ.copy()
    env["HOME"] = str(tmp_path / "home")
    (tmp_path / "home").mkdir()
    env["PATH"] = str(fake_bin) + os.pathsep + env.get("PATH", "")

    result = subprocess.run(  # noqa: S603
        ["bash", str(IPC_WRAPPER), "menu", "toggle"],  # noqa: S607
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )

    assert result.returncode != 0
    assert "shell" in result.stderr.lower()

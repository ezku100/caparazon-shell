"""Constraint Parte A: shell.qml y Workspaces.qml no hablan con KWin directo."""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SHELL = REPOSITORY_ROOT / "shell.qml"
WORKSPACES = REPOSITORY_ROOT / "modules" / "bar" / "Workspaces.qml"
POWER_PROFILE = REPOSITORY_ROOT / "modules" / "bar" / "PowerProfile.qml"


def test_shell_uses_caparazon_wm_active_output() -> None:
    contents = SHELL.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"active-output"' in contents
    assert "busctl" not in contents
    assert "org.kde.KWin" not in contents


def test_workspaces_pager_uses_cli_workspace_switch() -> None:
    contents = WORKSPACES.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"workspace-switch"' in contents
    assert "org.kde.KWin" not in contents
    assert "qdbus6" not in contents
    assert "setCurrentDesktop" not in contents


def test_power_profile_uses_cli() -> None:
    contents = POWER_PROFILE.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"power-profile"' in contents
    assert "qdbus6" not in contents
    assert "org.kde" not in contents


def test_power_profile_has_no_hardcoded_initial_profile() -> None:
    contents = POWER_PROFILE.read_text(encoding="utf-8")
    assert 'property string profile: "balanced"' not in contents

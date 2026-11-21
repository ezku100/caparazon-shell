"""Contrato: WorkspacesService habla con caparazon-wm, no con KWin."""

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SERVICE = REPOSITORY_ROOT / "modules" / "bar" / "WorkspacesService.qml"


def test_workspaces_service_uses_cli() -> None:
    contents = SERVICE.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"workspaces"' in contents
    assert '"watch-workspaces"' in contents


def test_workspaces_service_has_no_kwin_direct() -> None:
    contents = SERVICE.read_text(encoding="utf-8")
    assert "org.kde.KWin" not in contents
    assert "dbus-monitor" not in contents
    assert "VirtualDesktopManager" not in contents


def test_workspaces_service_keeps_public_api() -> None:
    contents = SERVICE.read_text(encoding="utf-8")
    assert "readonly property var desks" in contents
    assert "readonly property string currentId" in contents
    assert "function occupiedIds(" in contents
    assert "function screenCurrentId(" in contents
    assert "function refresh(" in contents

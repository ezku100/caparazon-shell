"""Contrato: ActiveWindowService habla con caparazon-wm (windows/watch-windows)."""

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SERVICE = REPOSITORY_ROOT / "modules" / "bar" / "ActiveWindowService.qml"
CLI = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-wm.py"


def test_active_window_service_uses_cli() -> None:
    contents = SERVICE.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"watch-windows"' in contents


def test_active_window_service_has_no_kwin_journal() -> None:
    contents = SERVICE.read_text(encoding="utf-8")
    assert "journalctl" not in contents
    assert "KWinActiveTitle" not in contents
    assert "_COMM=kwin_wayland" not in contents


def test_active_window_service_keeps_public_api() -> None:
    contents = SERVICE.read_text(encoding="utf-8")
    assert "property string appId" in contents
    assert "property string title" in contents
    assert "property var windowAppIds" in contents


def test_cli_has_windows_subcommands() -> None:
    contents = CLI.read_text(encoding="utf-8")
    assert 'cmd == "windows"' in contents
    assert 'cmd == "watch-windows"' in contents
    assert "def windows_state" in contents

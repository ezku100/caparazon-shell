"""Contrato del servicio de usuario que arranca la shell.

El arranque ya no es un ``.desktop`` de autostart: lo lleva un servicio de
systemd, así una actualización del repo no puede dejar la shell a medias.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
UNIT_TEMPLATE = (
    REPOSITORY_ROOT / "integration" / "systemd" / "caparazon-shell.service.in"
)
INSTALLER = REPOSITORY_ROOT / "install.sh"
LAUNCHER = REPOSITORY_ROOT / "scripts" / "caparazon-shell"


def test_the_unit_template_is_a_user_service() -> None:
    contents = UNIT_TEMPLATE.read_text(encoding="utf-8")

    assert "[Unit]" in contents
    assert "[Service]" in contents
    assert "[Install]" in contents
    assert "Type=exec" in contents
    assert "ExecStart=@SHELL_LAUNCHER@" in contents
    assert "Restart=on-failure" in contents
    assert "WantedBy=default.target" in contents


def test_the_unit_carries_the_qt_platform_theme() -> None:
    contents = UNIT_TEMPLATE.read_text(encoding="utf-8")

    assert "QT_QPA_PLATFORMTHEME=kde" in contents


def test_the_installer_writes_the_unit_and_enables_it() -> None:
    contents = INSTALLER.read_text(encoding="utf-8")

    assert "caparazon-shell.service" in contents
    assert "systemctl --user enable --now caparazon-shell.service" in contents
    assert "systemctl --user daemon-reload" in contents
    assert 'install_shell_service "$ACTIVE_SHELL_DIR"' in contents


def test_the_installer_drops_the_autostart_desktop() -> None:
    contents = INSTALLER.read_text(encoding="utf-8")

    assert 'rm -f "$AUTOSTART_DIR/caparazon.desktop"' in contents
    assert "app-caparazon@autostart.service" in contents


def test_the_installer_stops_writing_the_autostart_desktop() -> None:
    contents = INSTALLER.read_text(encoding="utf-8")

    assert '> "$AUTOSTART_DIR/caparazon.desktop"' not in contents


def test_the_launcher_stays_in_the_foreground_under_systemd() -> None:
    contents = LAUNCHER.read_text(encoding="utf-8")

    assert "INVOCATION_ID" in contents
    assert 'quickshell -p "$shell_dir" -d' in contents

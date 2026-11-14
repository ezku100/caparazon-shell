"""Cableado de la escala global: selector, fichero y arranque.

El valor lo elige Configs, lo guarda el panel y lo aplica el lanzador del
arranque automático; los tres tienen que hablar del mismo fichero.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "ShellConfigPanel.qml"
DESKTOP = REPOSITORY_ROOT / "integration" / "autostart" / "caparazon.desktop.in"
INSTALLER = REPOSITORY_ROOT / "install.sh"
GUARDIAN = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-guardian.sh"


def test_the_panel_offers_the_scale_selector() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert 'text: "Escala"' in contents
    for key in ('key: "0.5"', 'key: "0.75"', 'key: "1"', 'key: "1.25"', 'key: "1.5"'):
        assert key in contents
    assert "options: root.scaleRows" in contents
    assert "value: root.scaleValue" in contents


def test_the_panel_writes_the_scale_file_and_restarts() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert 'ThemeStyle.configDir + "/scale"' in contents
    assert "function setScale(key)" in contents
    assert 'os.replace(tmp, path)' in contents
    assert "systemctl --user restart app-caparazon@autostart.service" in contents
    assert '"setsid", "sh", "-c"' in contents


def test_the_scale_sits_before_the_colour_style() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert contents.index('text: "Escala"') < contents.index('text: "Estilo de color"')


def test_the_autostart_uses_the_scale_launcher() -> None:
    assert "Exec=@SHELL_PATH@/scripts/caparazon-shell" in DESKTOP.read_text(
        encoding="utf-8"
    )


def test_the_installer_and_guardian_still_find_the_shell() -> None:
    marker = "/scripts/caparazon-shell$"

    assert marker in INSTALLER.read_text(encoding="utf-8")
    assert marker in GUARDIAN.read_text(encoding="utf-8")


def test_the_installer_keeps_the_launcher_executable() -> None:
    """Sin permiso de ejecución el arranque muere con 203/EXEC."""
    contents = INSTALLER.read_text(encoding="utf-8")

    assert 'chmod 755 "$SHELL_DIR/scripts/caparazon-shell"' in contents


def test_the_repair_script_fixes_the_launch() -> None:
    """Un solo comando para quien no quiere tocar systemd a mano."""
    import os

    script = REPOSITORY_ROOT / "scripts" / "caparazon-repair"
    contents = script.read_text(encoding="utf-8")

    assert os.access(script, os.X_OK)
    assert "chmod 755" in contents
    assert "rewrite_autostart" in contents
    assert "daemon-reload" in contents
    assert "quickshell -p" in contents


def test_the_guardian_relaunches_a_missing_shell() -> None:
    """Si la shell no arranca, el vigilante la recupera solo."""
    contents = GUARDIAN.read_text(encoding="utf-8")

    assert "missing_polls=$((missing_polls + 1))" in contents
    assert 'setsid sh "$SHELL_PATH/scripts/caparazon-shell"' in contents

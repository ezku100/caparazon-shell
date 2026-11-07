"""El guardián reinicia la shell si Quickshell pierde el contexto gráfico.

Tras un `Graphics device lost` el proceso sigue vivo pero el scene graph se
reconstruye a medias: la barra se queda sin su cristal y sólo quedan los
iconos flotando. systemd no reinicia nada porque el proceso no muere, así
que un vigilante lee el log de Quickshell y reinicia el servicio.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
GUARDIAN = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-guardian.sh"
GUARDIAN_DESKTOP = (
    REPOSITORY_ROOT / "integration" / "autostart" / "caparazon-guardian.desktop.in"
)
INSTALL = REPOSITORY_ROOT / "install.sh"


def test_the_guardian_watches_for_the_lost_context_message() -> None:
    contents = GUARDIAN.read_text(encoding="utf-8")

    assert "Graphics device lost" in contents
    assert "systemctl --user restart" in contents


def test_the_guardian_follows_the_live_quickshell_log() -> None:
    """Cada arranque crea un `by-id` nuevo: el log se resuelve por PID."""
    contents = GUARDIAN.read_text(encoding="utf-8")

    assert "quickshell/by-pid" in contents
    assert "pgrep" in contents
    assert "log.log" in contents
    assert "tail -F" in contents
    assert "while true" in contents


def test_the_guardian_is_executable() -> None:
    assert GUARDIAN.stat().st_mode & 0o111


def test_the_guardian_desktop_entry_runs_the_script() -> None:
    contents = GUARDIAN_DESKTOP.read_text(encoding="utf-8")

    assert "Exec=@HOME@/.local/bin/caparazon-guardian.sh" in contents


def test_the_installer_registers_and_removes_the_guardian() -> None:
    contents = INSTALL.read_text(encoding="utf-8")

    assert "integration/bin/caparazon-guardian.sh" in contents
    assert "integration/autostart/caparazon-guardian.desktop.in" in contents
    assert '"$BIN_DIR/caparazon-guardian.sh"' in contents
    assert '"$AUTOSTART_DIR/caparazon-guardian.desktop"' in contents

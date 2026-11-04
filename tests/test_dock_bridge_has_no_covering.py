"""El puente no publica 'covering': el dock ya no lo necesita.

El dock pasó a ocultarse siempre y a anclarse con un botón de pin, así que la
detección de ventanas maximizadas sobró. Este test vigila que no vuelva a
colarse ese campo ni en el script de KWin ni en el demonio.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
BRIDGE = (
    REPOSITORY_ROOT
    / "integration"
    / "kwin"
    / "ezkudesktops"
    / "contents"
    / "code"
    / "main.js"
)
DAEMON = REPOSITORY_ROOT / "integration" / "bin" / "ezku-desktops-daemon.py"
SERVICE = REPOSITORY_ROOT / "modules" / "bar" / "ActiveWindowService.qml"
SHELL = REPOSITORY_ROOT / "shell.qml"
DOCK = REPOSITORY_ROOT / "modules" / "dock" / "Dock.qml"


def test_the_bridge_does_not_publish_covering() -> None:
    """Sin detección de ventanas maximizadas el puente no manda ese campo."""
    assert "covering" not in BRIDGE.read_text(encoding="utf-8")


def test_the_daemon_does_not_store_covering() -> None:
    """El demonio tampoco lo persiste: no queda código muerto."""
    assert "covering" not in DAEMON.read_text(encoding="utf-8")


def test_the_shell_does_not_wire_covering() -> None:
    """La shell tampoco habla de 'covering'."""
    assert "covering" not in SERVICE.read_text(encoding="utf-8")
    assert "covering" not in SHELL.read_text(encoding="utf-8")


def test_the_dock_does_not_read_covering() -> None:
    """El dock se aparta por el pin, no por lo que tapa una ventana."""
    assert "covering" not in DOCK.read_text(encoding="utf-8")

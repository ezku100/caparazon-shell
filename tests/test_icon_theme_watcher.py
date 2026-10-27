"""Contrato del cableado del vigilante del tema de iconos.

El vigilante es QML y no se puede probar sin levantar la shell, así que aquí
se comprueba lo que no debe cambiar por descuido: que el tipo esté
declarado, que la shell lo arranque una sola vez, que la decisión la tome
JavaScript y no el QML, y que espere antes de leer el archivo.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
QMLDIR = REPOSITORY_ROOT / "modules" / "icons" / "qmldir"
WATCHER = REPOSITORY_ROOT / "modules" / "icons" / "IconThemeWatcher.qml"
SHELL = REPOSITORY_ROOT / "shell.qml"


def test_the_watcher_is_declared_for_import() -> None:
    """El tipo nuevo está declarado en el qmldir para poder importarlo."""
    contents = QMLDIR.read_text(encoding="utf-8")

    assert "IconThemeWatcher 1.0 IconThemeWatcher.qml" in contents


def test_the_shell_starts_exactly_one_watcher() -> None:
    """La shell arranca un solo vigilante, no uno por pantalla."""
    contents = SHELL.read_text(encoding="utf-8")

    assert contents.count("IconThemeWatcher {") == 1
    assert 'import "modules/icons"' in contents


def test_the_watcher_delegates_the_decision() -> None:
    """La decisión la toma JavaScript: el QML sólo pregunta."""
    contents = WATCHER.read_text(encoding="utf-8")

    assert "IconTheme.iconTheme" in contents
    assert "IconTheme.themeDecision" in contents
    # El QML no compara el tema por su cuenta.
    assert "currentTheme !==" not in contents
    assert "currentTheme ==" not in contents


def test_the_watcher_waits_before_reading() -> None:
    """KConfig escribe el archivo en varias pasadas: hay que esperar."""
    contents = WATCHER.read_text(encoding="utf-8")

    assert "interval: 500" in contents
    assert "watchChanges: true" in contents


def test_the_watcher_keeps_checking_even_if_the_watch_is_lost() -> None:
    """Un fallo silencioso en la vigilancia dejaría el tema viejo."""
    contents = WATCHER.read_text(encoding="utf-8")

    assert "interval: 5000" in contents


def test_the_watcher_reads_the_process_state() -> None:
    """Para reiniciarse, el vigilante necesita saber dónde corre la shell."""
    contents = WATCHER.read_text(encoding="utf-8")

    assert "/proc/self/cgroup" in contents
    assert "/proc/$PPID/cmdline" in contents

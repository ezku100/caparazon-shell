"""El botón de aplicaciones de la barra usa el kanji de neko.

El logo de la distro sólo aparece si el tema de iconos lo trae, así que el
botón acababa con un icono genérico que no destacaba. Ahora muestra el kanji
猫 en el color de enfasis.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAUNCHER_BUTTON = REPOSITORY_ROOT / "modules" / "bar" / "LauncherButton.qml"


def test_the_launcher_shows_the_neko_kanji() -> None:
    """El botón de la barra muestra 猫 con la fuente CJK del tema."""
    contents = LAUNCHER_BUTTON.read_text(encoding="utf-8")

    assert 'text: "猫"' in contents
    assert "font.family: Theme.fontJP" in contents


def test_the_kanji_uses_the_emphasis_color() -> None:
    """El kanji va en el color de enfasis para que resalte en la barra."""
    contents = LAUNCHER_BUTTON.read_text(encoding="utf-8")

    assert "color: Theme.m3Primary" in contents


def test_the_launcher_does_not_resolve_the_distro_logo() -> None:
    """Nada de buscar el logo de la distro: no siempre está en el tema."""
    contents = LAUNCHER_BUTTON.read_text(encoding="utf-8")

    assert "distributor-logo" not in contents
    assert "pika-logo-duotone" not in contents
    assert "IconResolver" not in contents

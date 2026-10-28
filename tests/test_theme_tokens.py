"""Los tokens del tema tienen que existir de verdad.

Un `Theme.<token>` que no esta declarado en Theme.qml rompe el binding en
silencio: la propiedad se queda sin definir y el icono sale sin tinte. Este
test recorre los QML de la shell y comprueba que cada token usado existe.

Ademas fija el contrato de tinte del menu de sesion: apagado en reposo como
los iconos inactivos del dock, encendido al pasar el raton.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

THEME = REPOSITORY_ROOT / "theme" / "Theme.qml"
POWER_MENU = REPOSITORY_ROOT / "modules" / "bar" / "PowerMenu.qml"
DOCK_APP = REPOSITORY_ROOT / "modules" / "dock" / "DockApp.qml"

# `Theme.` sin punto ni letra delante para no capturar `IconTheme.js` ni
# `MatugenPalette.fgSurface`.
TOKEN_USE = re.compile(r"(?<![\w.])Theme\.([A-Za-z_][A-Za-z0-9_]*)")

TOKEN_DECLARED = re.compile(
    r"^\s*(?:readonly\s+)?property\s+\w+\s+([A-Za-z_][A-Za-z0-9_]*)\s*:",
    re.MULTILINE,
)

# El dock usa Theme.text en hover y Theme.textDim en reposo.
DOCK_TINT = re.compile(
    r"[Hh]over\.hovered\s*\?\s*Theme\.text\b\s*:\s*Theme\.textDim\b"
)

# El menú de sesión usa el color de enfasis (acento) en hover y Theme.textDim en reposo.
SESSION_MENU_TINT = re.compile(
    r"[Hh]over\.hovered\s*\?\s*Theme\.m3Primary\b\s*:\s*Theme\.textDim\b"
)


def qml_sources() -> list[Path]:
    """Todos los QML de la shell, en orden estable."""
    files = [REPOSITORY_ROOT / "shell.qml"]
    files += sorted((REPOSITORY_ROOT / "modules").rglob("*.qml"))
    files += sorted((REPOSITORY_ROOT / "components").rglob("*.qml"))
    return [path for path in files if path.is_file()]


def declared_tokens() -> set[str]:
    """Los tokens que Theme.qml declara de verdad."""
    contents = THEME.read_text(encoding="utf-8")
    return set(TOKEN_DECLARED.findall(contents))


@pytest.mark.parametrize("path", qml_sources(), ids=lambda path: path.name)
def test_every_theme_token_used_exists(path: Path) -> None:
    """Un token inexistente deja el icono sin color."""
    contents = path.read_text(encoding="utf-8")

    unknown = sorted(set(TOKEN_USE.findall(contents)) - declared_tokens())

    assert unknown == []


def test_the_dock_icons_are_dim_until_the_mouse_arrives() -> None:
    """El dock marca el hover con el color de texto y apaga el resto."""
    contents = DOCK_APP.read_text(encoding="utf-8")

    assert DOCK_TINT.search(contents)


def test_the_session_menu_icons_share_the_dock_tint() -> None:
    """El menu de sesion apaga sus iconos con textDim y enciende con acento al hover."""
    contents = POWER_MENU.read_text(encoding="utf-8")

    assert SESSION_MENU_TINT.search(contents)


def test_the_session_menu_icons_stay_big() -> None:
    """Los iconos del menu de sesion son protagonistas: no vuelven a 52 px."""
    contents = POWER_MENU.read_text(encoding="utf-8")

    match = re.search(r"implicitSize:\s*(\d+)", contents)

    assert match is not None
    assert int(match.group(1)) >= 64

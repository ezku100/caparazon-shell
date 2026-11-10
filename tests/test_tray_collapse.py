"""La bandeja de la barra se puede plegar y recuerda el estado."""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TRAY = REPOSITORY_ROOT / "modules" / "bar" / "Tray.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"


def test_the_tray_keeps_its_state_in_tray_json() -> None:
    contents = TRAY.read_text(encoding="utf-8")

    assert "tray.json" in contents
    assert "property bool collapsed" in contents
    assert "onCollapsedChanged" in contents


def test_the_default_state_is_expanded() -> None:
    contents = TRAY.read_text(encoding="utf-8")

    assert '\\"collapsed\\":false' in contents
    assert "property bool collapsed: false" in contents


def test_collapsing_hides_the_icons_and_keeps_the_toggle() -> None:
    contents = TRAY.read_text(encoding="utf-8")

    assert "visible: !root.collapsed" in contents
    assert "setCollapsed(!root.collapsed)" in contents
    assert "pan-end-symbolic" in contents


def test_the_arrow_turns_around_when_collapsed() -> None:
    contents = TRAY.read_text(encoding="utf-8")

    assert "rotation: root.collapsed ? 180 : 0" in contents


def test_the_bar_still_owns_the_tray() -> None:
    contents = BAR.read_text(encoding="utf-8")

    assert "Tray {" in contents
    assert "trayMenuState: bar.trayMenuState" in contents

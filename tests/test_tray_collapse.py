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


def test_collapsing_fades_the_icons_and_keeps_the_toggle() -> None:
    """Los iconos se funden (opacity 0) en vez de desaparecer de golpe."""
    contents = TRAY.read_text(encoding="utf-8")

    assert "opacity: root.collapsed ? 0 : 1" in contents
    assert "enabled: !root.collapsed" in contents
    assert "setCollapsed(!root.collapsed)" in contents
    assert "pan-end-symbolic" in contents


def test_folding_animates_the_capsule_and_the_icons() -> None:
    """El ancho de la cápsula, el recorte y el fundido van animados."""
    contents = TRAY.read_text(encoding="utf-8")

    assert "Behavior on width" in contents
    assert "clip: true" in contents
    assert "Behavior on open" in contents
    assert "anchors.rightMargin: root.capsulePad * root.open" in contents
    assert "+ (rep.count - 1 - index) * 22" in contents


def test_the_arrow_turns_around_when_collapsed() -> None:
    contents = TRAY.read_text(encoding="utf-8")

    assert "rotation: root.collapsed ? 180 : 0" in contents


def test_the_bar_still_owns_the_tray() -> None:
    contents = BAR.read_text(encoding="utf-8")

    assert "Tray {" in contents
    assert "trayMenuState: bar.trayMenuState" in contents


def test_the_folded_pill_matches_the_status_circles() -> None:
    """Plegada es un círculo de 26 con el acento y el icono en onPrimary."""
    contents = TRAY.read_text(encoding="utf-8")

    assert "root.collapsed ? 26 : root.capsuleHeight" in contents
    assert "root.collapsed ? 26 : 22" in contents
    assert "? Theme.m3OnPrimary" in contents
    assert "Qt.lighter(Theme.m3Primary, 1.08)" in contents

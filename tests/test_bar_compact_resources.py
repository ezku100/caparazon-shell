from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
MONITOR = REPOSITORY_ROOT / "modules" / "bar" / "ResourceMonitor.qml"


def test_the_compact_bar_shows_the_rings_only_with_the_tray_folded() -> None:
    """En barra compacta los anillos aparecen cuando la bandeja se pliega."""
    contents = BAR.read_text(encoding="utf-8")

    assert "readonly property bool shown: !bar.compactBar || tray.collapsed" in contents
    assert "opacity: shown ? 1 : 0" in contents


def test_the_rings_fade_instead_of_popping() -> None:
    contents = BAR.read_text(encoding="utf-8")

    assert "visible: opacity > 0" in contents
    assert "Behavior on opacity" in contents
    assert "x: resourceMonitor.shown ? 0 : 10" in contents


def test_the_rings_still_follow_the_monitor_options() -> None:
    """Los anillos que se ven son los que no están apagados en el panel."""
    contents = MONITOR.read_text(encoding="utf-8")

    assert 'visible: !root.isHidden("cpu")' in contents
    assert 'visible: !root.isHidden("temp")' in contents

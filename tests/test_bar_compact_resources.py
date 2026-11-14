from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
MONITOR = REPOSITORY_ROOT / "modules" / "bar" / "ResourceMonitor.qml"


def test_the_compact_bar_shows_the_rings_only_with_the_tray_folded() -> None:
    """En barra compacta los anillos aparecen cuando la bandeja se pliega."""
    contents = BAR.read_text(encoding="utf-8")

    assert "!bar.compactBar || tray.collapsed" in contents
    assert "opacity: ringsShown ? 1 : 0" in contents


def test_the_rings_fade_instead_of_popping() -> None:
    contents = BAR.read_text(encoding="utf-8")

    assert "visible: !bar.vertical && opacity > 0" in contents
    assert "Behavior on opacity" in contents
    assert "x: resourceMonitor.ringsShown ? 0 : 10" in contents


def test_the_vertical_rings_step_aside_when_the_tray_unfolds() -> None:
    """En vertical la bandeja crece hacia arriba: los anillos se apartan."""
    contents = BAR.read_text(encoding="utf-8")

    # El monitor vertical usa la misma regla que el horizontal: se apaga
    # con la bandeja desplegada y se desvanece en vez de aparecer de golpe.
    # Va despues de la bandeja (se apoya sobre ella), asi que el bloque se
    # recorta hasta el cierre del item.
    start = contents.index("id: resourceMonitorV")
    end = contents.index("\n            }", start)
    block = contents[start:end]

    assert "readonly property bool ringsShown: trayV.collapsed" in block
    assert "opacity: ringsShown ? 1 : 0" in block
    assert "visible: bar.vertical && opacity > 0" in block
    assert "Behavior on opacity" in block


def test_the_rings_still_follow_the_monitor_options() -> None:
    """Los anillos que se ven son los que no están apagados en el panel."""
    contents = MONITOR.read_text(encoding="utf-8")

    assert 'visible: !root.isHidden("cpu")' in contents
    assert 'visible: !root.isHidden("temp")' in contents

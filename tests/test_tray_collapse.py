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
    assert "id: toggle" in contents


def test_folding_animates_the_capsule_and_the_icons() -> None:
    """El ancho de la cápsula, el recorte y el fundido van animados."""
    contents = TRAY.read_text(encoding="utf-8")

    assert "Behavior on width" in contents
    assert "clip: true" in contents
    assert "Behavior on open" in contents
    assert "anchors.rightMargin: root.capsulePad * root.open" in contents
    assert "+ (rep.count - 1 - index) * 22" in contents


def test_the_arrow_turns_around_when_collapsed() -> None:
    """Horizontal gira 180; en vertical la flecha apunta al interior."""
    contents = TRAY.read_text(encoding="utf-8")

    assert "rotation: root.vertical" in contents
    assert "(root.collapsed ? 180 : 0)" in contents


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


def test_the_vertical_tray_keeps_its_width_when_it_unfolds() -> None:
    """En vertical la bandeja crece en alto, nunca en ancho.

    Si el ancho variase, el grupo de la barra se re-anchuraba y la bandeja
    junto con los botones de sistema se iban de lado.
    """
    contents = TRAY.read_text(encoding="utf-8")

    assert "width: root.vertical\n        ? 26" in contents
    assert "width: root.vertical ? 26 : root.width" in contents
    assert "root.collapsed ? 26 : capsuleHeight" not in contents


def test_the_vertical_groups_keep_their_width_when_the_tray_unfolds() -> None:
    """Los grupos verticales tienen ancho fijo y centran a sus hijos.

    Con una Column, el ancho del grupo lo definia el hijo mas ancho: al
    desplegarse la bandeja, el grupo se re-anchuraba y sus hijos, alineados
    al borde izquierdo, se desplazaban de lado.
    """
    contents = BAR.read_text(encoding="utf-8")

    assert "import QtQuick.Layouts" in contents
    lines = contents.splitlines()
    for group in ("verticalTop", "verticalCenter"):
        start = next(i for i, line in enumerate(lines) if f"id: {group}" in line)
        end = next(
            i
            for i in range(start, len(lines))
            if lines[i].rstrip() == "            }"
        )
        block = "\n".join(lines[start - 1 : end])

        assert "ColumnLayout {" in block
        assert "width: Theme.barHeight" in block
        assert "Layout.fillWidth: false" in block
        assert "Layout.alignment: Qt.AlignHCenter" in block


def test_the_vertical_footer_hangs_from_the_bottom_instead_of_flowing() -> None:
    """El pie se ancla: iconos abajo, bandeja encima y anillos encima de ella.

    Si el grupo fluyera en una columna, al plegarse la bandeja el layout se
    recomponia y su borde inferior se iba hacia abajo.
    """
    contents = BAR.read_text(encoding="utf-8")

    assert "id: verticalStatusIcons" in contents
    assert "bottom: verticalStatusIcons.top" in contents
    assert "bottom: trayV.top" in contents



def test_the_fold_chevron_is_anchored_to_the_capsule() -> None:
    """El chevron se centra en el círculo de fondo, no en la celda del Grid.

    El Grid deja holgura en su última celda y el triángulo quedaba 2 px
    descentrado; anclado a la cápsula comparte su centro exacto.
    """
    contents = TRAY.read_text(encoding="utf-8")

    assert "anchors.right: root.vertical ? undefined : capsule.right" in contents
    assert (
        "anchors.verticalCenter: root.vertical ? undefined : capsule.verticalCenter"
        in contents
    )
    assert "anchors.bottom: root.vertical ? capsule.bottom : undefined" in contents


def test_the_fold_chevron_is_drawn_instead_of_the_theme_icon() -> None:
    """El glifo del tema traía aire asimétrico; el trazo se dibuja."""
    contents = TRAY.read_text(encoding="utf-8")

    assert "ShapePath.RoundCap" in contents
    assert "startX: chevron.centerX - chevron.halfWidth" in contents
    assert "pan-end-symbolic" not in contents

"""Los menús son sólidos salvo el de apagado.

`BackgroundEffect.blurRegion` pide al compositor difuminar el fondo de la
ventana (`ext-background-effect-v1`). En el menú de apagado/sesión es
deliberado: el scrim a pantalla completa se apoya en el escritorio
desenfocado. En el menú de apps y en el segundo menú la tarjeta es opaca y
el efecto sólo asomaba como un destello tipo cristal esmerilado entre los
frames de apertura y cierre.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
APP_MENU = REPOSITORY_ROOT / "modules" / "appmenu" / "AppMenu.qml"
SECOND_MENU = REPOSITORY_ROOT / "modules" / "secondmenu" / "SecondMenu.qml"
POWER_MENU = REPOSITORY_ROOT / "modules" / "bar" / "PowerMenu.qml"


def test_the_opaque_cards_do_not_request_desktop_blur() -> None:
    for path in (APP_MENU, SECOND_MENU):
        contents = path.read_text(encoding="utf-8")

        assert "BackgroundEffect" not in contents, (
            f"{path.name}: la tarjeta es opaca, quita el blur del escritorio"
        )


def test_the_power_menu_keeps_its_deliberate_blur() -> None:
    contents = POWER_MENU.read_text(encoding="utf-8")

    assert "BackgroundEffect.blurRegion" in contents, (
        "el menú de apagado/sesión sí lleva desenfoque a propósito"
    )


def test_the_power_menu_ignores_exclusive_zones_at_scaled_dprs() -> None:
    """La capa debe cubrir barra y dock también con QT_SCALE_FACTOR < 1.

    Quickshell 0.3.2 escala el centinela ``-1`` de ``ExclusionMode.Ignore``;
    con DPR 0.5 o 0.75 llega a KWin como ``0``, que significa respetar las
    zonas exclusivas. Un valor negativo suficientemente distante de cero conserva
    la semántica de "ignorar exclusivas" en todas las escalas soportadas.
    """
    contents = POWER_MENU.read_text(encoding="utf-8")

    assert "exclusiveZone: -2" in contents, (
        "el menú de sesión debe ignorar las zonas exclusivas de barra y dock"
    )
    assert "exclusionMode: ExclusionMode.Ignore" not in contents, (
        "ExclusionMode.Ignore pierde su centinela al aplicar QT_SCALE_FACTOR"
    )

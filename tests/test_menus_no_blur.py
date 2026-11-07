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

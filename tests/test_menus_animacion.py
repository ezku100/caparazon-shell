"""Contrato del lenguaje de animacion unificado de los tres menus.

El menu "crece" desde el centro: escala 0.92 -> 1 con rebote sutil
(OutBack overshoot 1.2) al abrir, InCubic al cerrar. Y baja de entrada
14 px, la opacidad se adelanta a la escala, el brillo del borde llega
70 ms tarde y el contenido acompana escalonado (tiles, rail, panel).
Abrid 260 ms, cerrad 170 ms: agil.

Ademas las ventanas de menu se montan siempre: si el Loader las
recreara al abrir, el componente naceria ya en reposo y ningun Behavior
tendria nada que animar.
"""

import re
from pathlib import Path

WAVE_STEP_MS = 10
MAX_WAVE_MS = 150
RAIL_STEP_MS = 45
GLOW_DELAY_MS = 70

APPMENU = Path("modules/appmenu/AppMenu.qml")
SECONDMENU = Path("modules/secondmenu/SecondMenu.qml")
POWERMENU = Path("modules/bar/PowerMenu.qml")
BAR = Path("modules/bar/Bar.qml")


def source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def card_block(path: Path, marker: str, end: str | None = None) -> str:
    text = source(path)
    start = text.index(marker)
    text = text[start:]
    if end is not None:
        return text[:text.index(end)]
    return text[:20000]


def grid_block() -> str:
    text = source(APPMENU)
    start = text.index("delegate: Item {")
    return text[start:text.index("Keys.onEscapePressed", start)]


def loader_block(component: str) -> str:
    bar = source(BAR)
    at = bar.index(f"sourceComponent: {component}")
    start = bar.rindex("Loader {", 0, at)
    return bar[start:bar.index("}", at)]


def test_los_tres_menus_declaran_tiempos_abrir_y_cerrar() -> None:
    for path in (APPMENU, SECONDMENU, POWERMENU):
        text = source(path)
        assert re.search(r"readonly property int animOpen: 260\b", text), (
            f"{path}: falta animOpen: 260"
        )
        assert re.search(r"readonly property int animClose: 170\b", text), (
            f"{path}: falta animClose: 170"
        )


def test_la_tarjeta_crece_desde_el_centro_con_rebote() -> None:
    for path, marker, end in (
        (APPMENU, "id: card", "id: searchBox"),
        (SECONDMENU, "id: card", "MultiEffect"),
        (POWERMENU, "id: content", "Fase de despedida"),
    ):
        block = card_block(path, marker, end)
        easing_cond = "easing.type: root.active ? Easing.OutBack : Easing.InCubic"
        assert "0.92" in block, f"{path}: la tarjeta debe partir de 0.92"
        assert easing_cond in block, (
            f"{path}: falta OutBack al abrir / InCubic al cerrar"
        )
        assert "easing.overshoot: 1.2" in block, (
            f"{path}: el rebote sutil debe ser overshoot 1.2"
        )
        assert re.search(r"y: root\.active \? 0 : 14\b", block), (
            f"{path}: falta el desplazamiento de 14 px"
        )


def test_la_opacidad_se_adelanta_un_poco_a_la_escala() -> None:
    for path, marker, end in (
        (APPMENU, "id: card", "id: searchBox"),
        (SECONDMENU, "id: card", "MultiEffect"),
        (POWERMENU, "id: content", "Fase de despedida"),
    ):
        block = card_block(path, marker, end)
        assert "duration: root.active ? 200 : root.animClose" in block, (
            f"{path}: la opacidad debe correr 200 ms al abrir"
        )


def test_el_glow_del_borde_llega_tarde() -> None:
    for path in (APPMENU, SECONDMENU):
        text = source(path)
        assert "shadowOpacity: root.active ? 0.38 : 0" in text, (
            f"{path}: el brillo debe apagarse al cerrar"
        )
        assert (
            f"duration: root.active ? {GLOW_DELAY_MS} : 0" in text
        ), f"{path}: el brillo debe desfazar {GLOW_DELAY_MS} ms"


def test_el_scrim_usa_el_tiempo_abrir_o_cerrar() -> None:
    for path in (APPMENU, SECONDMENU):
        assert re.search(
            r"opened ? \? (root\.)*animOpen : (root\.)*animClose", source(path)
        ), f"{path}: el scrim debe elegir entre animOpen y animClose"


def test_los_tiles_del_menu_de_apps_entran_en_ola_con_micro_pop() -> None:
    grid = grid_block()
    wave = f"Math.min(index * {WAVE_STEP_MS}, {MAX_WAVE_MS})"
    assert wave in grid, "falta la ola capped de los tiles"
    assert "root.active ?" in grid, "la ola debe anularse al cerrar"
    assert re.search(r"easing\.overshoot: 1\.0[1-9]", grid), (
        "los tiles deben entrar con micro-pop"
    )


def test_el_menu_de_sesion_conserva_su_scrim_fuerte_y_farewell() -> None:
    text = source(POWERMENU)
    assert "scrim.opacity = 0.52" in text, "el scrim 0.52 del farewell no se toca"
    assert "farewellHold" in text, "el menu de sesion conserva su farewell"


def test_el_submenu_acompana_con_rail_y_panel() -> None:
    text = source(SECONDMENU)
    assert f"index * {RAIL_STEP_MS}" in text, "falta el desfase del rail"
    assert "panelLoader" in text, "el panel debe tener lift propio"
    assert re.search(r"y: root\.active \? 0 : 16\b", text), (
        "el panel se asienta desde 16 px"
    )


def test_los_menus_no_se_recrean_en_cada_apertura() -> None:
    # Si el Loader recreara la ventana al abrir, el componente naceria ya
    # en reposo y los Behavior de apertura no tendrian nada que animar.
    for component in ("PowerMenu", "AppMenu", "SecondMenu"):
        block = loader_block(component)
        assert "active: true" in block, (
            f"el Loader de {component} debe montar la ventana siempre"
        )
    bar = source(BAR)
    assert "bar.appMenuState.opened" not in bar, (
        "el Loader no debe depender de opened/closing"
    )


def test_los_menus_solo_se_mapean_en_la_pantalla_que_abrio() -> None:
    for path in (APPMENU, SECONDMENU, POWERMENU):
        assert "root.menuState.activeScreen === root.screen" in source(path), (
            f"{path}: el menu debe mapearse solo en su pantalla"
        )


def test_el_cierre_no_espera_mas_de_lo_que_dura_la_animacion() -> None:
    for path in (APPMENU, SECONDMENU, POWERMENU):
        assert re.search(
            r"id: closeTimer\s*\n\s*interval: root\.animClose \+ 20", source(path)
        ), f"{path}: closeTimer debe esperar animClose + 20"

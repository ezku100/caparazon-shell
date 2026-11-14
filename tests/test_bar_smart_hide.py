"""Contrato de los estados de la barra dinámica.

La barra puede quedarse anclada (siempre visible, reservando su franja) o
volverse dinámica: se aparta al filo y vuelve al pasar el ratón. Toda esa
lógica vive en ``modules/bar/BarSmartHide.js`` como funciones puras, así que
se puede ejecutar con node y comprobar sin levantar la shell.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "bar_smart_hide_harness.js"


class StateCase(TypedDict):
    """Resultado de un escenario de estado de la barra."""

    ok: bool
    expected: object
    value: object
    detail: str


def run_cases() -> dict[str, StateCase]:
    """Ejecuta los escenarios de la barra y devuelve sus resultados."""
    node = shutil.which("node")
    if node is None:
        pytest.skip("node no disponible")
    runner = node or "node"
    result = subprocess.run(  # noqa: S603
        [runner, str(HARNESS)],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    payload = cast("dict[str, object]", json.loads(result.stdout))
    return cast("dict[str, StateCase]", payload)


CASES = run_cases()


@pytest.mark.parametrize("case_id", sorted(CASES))
def test_the_bar_follows_its_smart_hide_states(case_id: str) -> None:
    """Cada escenario de la barra debe cumplirse."""
    case = CASES[case_id]

    assert case["ok"], (
        f"{case_id}: se esperaba {case['expected']!r} y se obtuvo {case['value']!r}"
        f" ({case['detail']})"
    )


def test_the_dynamic_bar_keeps_a_hot_edge_on_every_border() -> None:
    """Apartada, la barra deja una franja con la que se puede volver a llamar."""
    assert CASES["mascara-oculta-arriba"]["value"] == {
        "x": 0,
        "y": 0,
        "width": 1920,
        "height": 6,
    }
    assert CASES["mascara-oculta-izquierda"]["value"] == {
        "x": 0,
        "y": 0,
        "width": 6,
        "height": 1920,
    }


def test_the_dynamic_bar_does_not_reserve_screen_space() -> None:
    """Sólo la barra anclada empuja las ventanas: la dinámica las deja llegar."""
    assert CASES["dinamica-no-reserva"]["value"] == 0
    assert CASES["anclada-reserva-franja"]["value"] == 40

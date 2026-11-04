"""Contrato de los estados del dock inteligente.

El dock se aparta cuando una ventana ocupa la pantalla, vuelve al borde al
acercar el ratón y se retira otra vez al dejarlo. Toda esa lógica vive en
``modules/dock/DockSmartHide.js`` como funciones puras, así que se puede
ejecutar con node y comprobar sin levantar la shell.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "dock_smart_hide_harness.js"


class StateCase(TypedDict):
    """Resultado de un escenario de estado del dock."""

    ok: bool
    expected: object
    value: object
    detail: str


def run_cases() -> dict[str, StateCase]:
    """Ejecuta los escenarios del dock y devuelve sus resultados."""
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
def test_the_dock_follows_its_smart_hide_states(case_id: str) -> None:
    """Cada escenario del dock debe cumplirse."""
    case = CASES[case_id]

    assert case["ok"], (
        f"{case_id}: se esperaba {case['expected']!r} y se obtuvo {case['value']!r}"
        f" ({case['detail']})"
    )

def test_the_dock_keeps_a_hot_edge_at_the_bottom() -> None:
    """Apartado, el dock deja una franja con la que se puede volver a llamar."""
    case = CASES["mascara-oculta"]

    assert case["value"] == {"x": 780, "y": 58, "width": 360, "height": 6}

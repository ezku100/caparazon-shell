"""Contrato de la lógica del calendario del menú secundario.

La rejilla del mes se calcula en ``modules/secondmenu/CalendarMath.js``; aquí
se ejecuta ese archivo con node para comprobar que la semana empieza en lunes,
que febrero respeta el año bisiesto y que la rejilla siempre son 6x7 celdas.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "calendar_math_harness.js"


class CalendarCase(TypedDict):
    """Resultado de un escenario del calendario."""

    ok: bool
    expected: object
    value: object
    detail: str


def run_cases() -> dict[str, CalendarCase]:
    """Ejecuta los escenarios del calendario y devuelve sus resultados."""
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
    return cast("dict[str, CalendarCase]", payload)


CASES = run_cases()


@pytest.mark.parametrize("case_id", sorted(CASES))
def test_the_calendar_grid_matches_its_contract(case_id: str) -> None:
    """Cada escenario del calendario debe cumplirse."""
    case = CASES[case_id]

    assert case["ok"], (
        f"{case_id}: se esperaba {case['expected']!r} y se obtuvo {case['value']!r}"
        f" ({case['detail']})"
    )


def test_the_month_grid_starts_on_monday() -> None:
    """La primera celda de octubre de 2026 es el lunes 28 de septiembre."""
    case = CASES["primera-celda"]

    assert case["value"] == 28

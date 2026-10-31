"""Contrato de la lógica del espectro del modo compacto de Música.

El mapeo de bytes a niveles, el suavizado y el degradado viven en
``modules/music/SpectrumMath.js``; aquí se ejecuta con node y se comprueba
también el cableado del panel.
"""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "spectrum_math_harness.js"
SPECTRUM_MATH = REPOSITORY_ROOT / "modules" / "music" / "SpectrumMath.js"


@dataclass(frozen=True, slots=True)
class SpectrumCase:
    """Resultado de un escenario del espectro."""

    ok: bool
    detail: str


def run_cases() -> dict[str, SpectrumCase]:
    """Ejecuta los escenarios del espectro y devuelve sus resultados."""
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

    cases: dict[str, SpectrumCase] = {}
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        case_id, verdict, detail = parts
        cases[case_id] = SpectrumCase(ok=verdict == "PASS", detail=detail)
    return cases


CASES = run_cases()


def contents(path: Path) -> str:
    """Devuelve el contenido de un archivo del repositorio."""
    return path.read_text(encoding="utf-8")


@pytest.mark.parametrize("case_id", sorted(CASES))
def test_the_spectrum_math_contract(case_id: str) -> None:
    """Cada escenario del espectro debe cumplirse."""
    case = CASES[case_id]

    assert case.ok, case.detail


def test_the_spectrum_math_module_exists() -> None:
    """La lógica del espectro vive en un módulo propio."""
    assert SPECTRUM_MATH.is_file()

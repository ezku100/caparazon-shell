"""Contrato del emparejamiento entre una ventana y su .desktop.

El dock decide qué icono poner a cada app en ejecución comparando el appId
que publica KWin con las entradas de .desktop que escanea Quickshell. Aquí se
comprueba ese emparejamiento sin levantar la shell: el código vive en
``modules/dock/DockEntries.js`` y se ejecuta con node.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "dock_entries_harness.js"


class MatchCase(TypedDict):
    """Resultado de un escenario de emparejamiento."""

    ok: bool
    expected: object
    value: object
    detail: str


def run_cases() -> dict[str, MatchCase]:
    """Ejecuta los escenarios del emparejamiento y devuelve sus resultados."""
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
    return cast("dict[str, MatchCase]", payload)


CASES = run_cases()


@pytest.mark.parametrize("case_id", sorted(CASES))
def test_the_dock_matches_windows_with_their_desktop_entry(case_id: str) -> None:
    """Cada escenario del emparejamiento debe cumplirse."""
    case = CASES[case_id]

    assert case["ok"], (
        f"{case_id}: se esperaba {case['expected']!r} y se obtuvo {case['value']!r}"
        f" ({case['detail']})"
    )


def test_the_prism_launcher_window_finds_its_desktop_entry() -> None:
    """Prism publica org.prismlauncher.PrismLauncher y su .desktop es prism_launcher."""
    case = CASES["prism-por-clase-de-arranque"]

    assert case["value"] is True

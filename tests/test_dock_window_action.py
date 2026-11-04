"""Contrato de la acción de ventana del dock.

Un clic en el icono de una app abierta la enfoca; el siguiente clic la
minimiza y el siguiente la restaura. La decisión la toma KWin, porque es el
único sitio donde se sabe si una ventana está minimizada: KWin 6.7.4 no
implementa ext-foreign-toplevel-management y Quickshell no ve ese estado.

La lógica vive en ``modules/bar/KWinWindowAction.js`` y se ejecuta con node
contra un ``workspace`` falso, sin levantar la shell.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "kwin_window_action_harness.js"
DOCK = REPOSITORY_ROOT / "modules" / "dock" / "Dock.qml"
OLD_SCRIPT = REPOSITORY_ROOT / "modules" / "bar" / "KWinFocusApp.js"


class ActionCase(TypedDict):
    """Resultado de un escenario de la acción de ventana."""

    ok: bool
    expected: object
    value: object
    detail: str


def run_cases() -> dict[str, ActionCase]:
    """Ejecuta los escenarios de la acción de ventana y devuelve sus resultados."""
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
    return cast("dict[str, ActionCase]", payload)


CASES = run_cases()


@pytest.mark.parametrize("case_id", sorted(CASES))
def test_the_window_action_follows_the_expected_rules(case_id: str) -> None:
    """Cada escenario de la acción de ventana debe cumplirse."""
    case = CASES[case_id]

    assert case["ok"], (
        f"{case_id}: se esperaba {case['expected']!r} y se obtuvo {case['value']!r}"
        f" ({case['detail']})"
    )


def test_the_second_click_on_the_focused_app_minimizes_it() -> None:
    """Con la app enfocada, el clic la minimiza."""
    case = CASES["la-app-enfocada-se-minimiza"]

    assert case["value"] == {
        "action": "minimize",
        "minimized": ["kitty"],
        "activated": [],
    }


def test_clicking_a_minimized_window_restores_it() -> None:
    """Una ventana escondida vuelve y se enfoca."""
    case = CASES["la-ventana-minimizada-se-restaura"]

    assert case["value"] == {
        "action": "restore",
        "minimized": [],
        "activated": ["zen"],
    }


def test_clicking_an_app_in_the_background_only_focuses_it() -> None:
    """Una app que no está enfocada se enfoca, pero no se minimiza."""
    case = CASES["la-app-en-segundo-plano-se-enfoca"]

    assert case["value"] == {
        "action": "focus",
        "minimized": [],
        "activated": ["discord"],
    }


def test_the_dock_asks_kwin_for_the_window_action() -> None:
    """El dock carga el script de la acción de ventana."""
    dock = DOCK.read_text(encoding="utf-8")

    assert "KWinWindowAction.js" in dock
    assert "windowActionProcess.active = dock.activeAppId" in dock


def test_the_old_focus_script_is_gone() -> None:
    """El script que sólo enfocaba queda muerto y se elimina."""
    assert not OLD_SCRIPT.exists()
    assert "KWinFocusApp.js" not in DOCK.read_text(encoding="utf-8")

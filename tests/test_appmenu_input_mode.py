"""Contrato del selector del menú central: teclado y ratón se turnan."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "input_mode_harness.js"


class SelectorCase(TypedDict):
    """Resultado de un escenario del selector."""

    id: str
    name: str
    ok: bool
    detail: str


def run_cases() -> dict[str, SelectorCase]:
    """Ejecuta los escenarios del selector y devuelve sus resultados por id."""
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
    raw = cast("list[SelectorCase]", payload["cases"])
    return {case["id"]: case for case in raw}


def assert_case(cases: dict[str, SelectorCase], case_id: str) -> None:
    """Falla si el escenario indicado no se cumple."""
    case = cases.get(case_id)
    assert case is not None, f"escenario ausente: {case_id}"
    assert case["ok"], f"{case['name']}: {case['detail']}"


def test_arrow_keys_take_over_the_selector() -> None:
    cases = run_cases()
    assert_case(cases, "arrow_keys_activate_keyboard_mode")


def test_pointer_jitter_does_not_steal_the_keyboard_selection() -> None:
    cases = run_cases()
    assert_case(cases, "tiny_pointer_jitter_keeps_keyboard_mode")


def test_real_pointer_movement_returns_control_to_the_mouse() -> None:
    cases = run_cases()
    assert_case(cases, "real_pointer_movement_returns_control_to_mouse")
    assert_case(cases, "pointer_movement_accumulates_between_events")
    assert_case(cases, "mouse_mode_keeps_cursor_on_hovered_app")


def test_hover_follows_the_mouse_only_while_the_mouse_is_active() -> None:
    cases = run_cases()
    assert_case(cases, "hover_moves_cursor_while_mouse_is_active")
    assert_case(cases, "hover_does_not_move_cursor_in_keyboard_mode")
    assert_case(cases, "hover_exit_clears_the_hovered_index")


def test_typing_returns_control_to_the_keyboard() -> None:
    cases = run_cases()
    assert_case(cases, "typing_returns_control_to_keyboard")


def test_arrows_continue_from_the_hovered_app() -> None:
    cases = run_cases()
    assert_case(cases, "arrows_continue_from_the_hovered_app")


def test_grid_movement_stays_inside_the_list() -> None:
    cases = run_cases()
    assert_case(cases, "vertical_moves_jump_one_row")
    assert_case(cases, "down_from_the_last_row_stays")
    assert_case(cases, "down_clamps_to_the_last_item")
    assert_case(cases, "horizontal_moves_stay_inside_the_grid")


def test_reset_returns_the_cursor_to_the_first_app() -> None:
    cases = run_cases()
    assert_case(cases, "reset_returns_cursor_to_first_app")
    assert_case(cases, "initial_state")

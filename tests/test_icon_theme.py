"""Contrato del tema de iconos: qué se lee y cuándo hay que reiniciar."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "icon_theme_harness.js"


class IconCase(TypedDict):
    """Resultado de un escenario del tema de iconos."""

    id: str
    name: str
    ok: bool
    detail: str


def run_cases() -> dict[str, IconCase]:
    """Ejecuta los escenarios y devuelve sus resultados por id."""
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
    raw = cast("list[IconCase]", payload["cases"])
    return {case["id"]: case for case in raw}


def assert_case(cases: dict[str, IconCase], case_id: str) -> None:
    """Falla si el escenario indicado no se cumple."""
    case = cases.get(case_id)
    assert case is not None, f"escenario ausente: {case_id}"
    assert case["ok"], f"{case['name']}: {case['detail']}"


def test_the_icon_theme_is_read_from_the_icons_section() -> None:
    cases = run_cases()
    assert_case(cases, "theme_is_read_from_the_icons_section")
    assert_case(cases, "value_is_trimmed")


def test_a_missing_section_or_key_gives_no_theme() -> None:
    cases = run_cases()
    assert_case(cases, "missing_section_gives_empty")
    assert_case(cases, "missing_key_gives_empty")
    assert_case(cases, "empty_text_gives_empty")


def test_other_sections_and_comments_are_ignored() -> None:
    cases = run_cases()
    assert_case(cases, "other_sections_are_ignored")
    assert_case(cases, "comments_are_ignored")
    assert_case(cases, "theme_stops_at_the_next_section")


def test_a_new_theme_asks_for_a_restart() -> None:
    cases = run_cases()
    assert_case(cases, "a_new_theme_asks_for_a_restart")


def test_the_same_or_an_empty_theme_keeps_the_shell() -> None:
    cases = run_cases()
    assert_case(cases, "the_same_theme_keeps_the_shell")
    assert_case(cases, "empty_value_keeps_the_previous_theme")


def test_the_first_observed_theme_is_only_a_baseline() -> None:
    cases = run_cases()
    assert_case(cases, "first_observed_theme_is_only_a_baseline")
    assert_case(cases, "a_theme_that_appears_later_asks_for_a_restart")


def test_the_restart_command_prefers_a_transient_unit() -> None:
    cases = run_cases()
    assert_case(cases, "the_restart_command_uses_a_transient_unit")


def test_the_restart_command_falls_back_to_systemctl() -> None:
    cases = run_cases()
    assert_case(cases, "the_restart_command_falls_back_to_systemctl")


def test_the_relaunch_command_waits_for_the_pid() -> None:
    cases = run_cases()
    assert_case(cases, "the_relaunch_command_waits_for_the_pid")

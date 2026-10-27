"""Contrato del resolvedor de iconos: qué nombres alternativos se prueban."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "icon_names_harness.js"


class IconCase(TypedDict):
    """Resultado de un escenario de nombres de icono."""

    id: str
    name: str
    ok: bool
    detail: str


def run_cases() -> dict[str, IconCase]:
    """Ejecuta los escenarios de nombres y devuelve sus resultados por id."""
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


def test_the_exact_name_is_always_tried_first() -> None:
    cases = run_cases()
    assert_case(cases, "exact_name_comes_first")


def test_symbolic_and_lowercase_variants_are_offered() -> None:
    cases = run_cases()
    assert_case(cases, "symbolic_suffix_is_offered_without_the_suffix")
    assert_case(cases, "lowercase_variant_is_offered")


def test_reverse_dns_ids_offer_their_suffixes() -> None:
    cases = run_cases()
    assert_case(cases, "reverse_dns_suffixes_are_offered")


def test_candidates_are_unique_and_meaningful() -> None:
    cases = run_cases()
    assert_case(cases, "duplicates_are_removed")
    assert_case(cases, "plain_name_keeps_only_useful_variants")


def test_empty_names_and_paths_propose_nothing() -> None:
    cases = run_cases()
    assert_case(cases, "empty_name_has_no_candidates")
    assert_case(cases, "absolute_path_has_no_candidates")

def test_absolute_paths_and_file_urls_are_told_apart() -> None:
    cases = run_cases()
    assert_case(cases, "absolute_path_is_a_path")
    assert_case(cases, "file_url_is_a_url")


def test_theme_names_and_blanks_are_told_apart() -> None:
    cases = run_cases()
    assert_case(cases, "theme_name_is_a_name")
    assert_case(cases, "blank_name_is_empty")

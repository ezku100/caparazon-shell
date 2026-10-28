"""Contrato de los iconos de la barra: que nombre de tema pide cada estado."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import TypedDict, cast

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "bar_icons_harness.js"


class IconCase(TypedDict):
    """Resultado de un escenario de los iconos de la barra."""

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


def test_the_session_menu_uses_theme_icons() -> None:
    """Cada accion del menu de sesion pide su icono por nombre."""
    cases = run_cases()
    assert_case(cases, "session_lock")
    assert_case(cases, "session_logout")
    assert_case(cases, "session_shutdown")
    assert_case(cases, "session_reboot")


def test_an_unknown_session_action_invents_nothing() -> None:
    """Una accion que no esta en la tabla no devuelve nombres."""
    cases = run_cases()
    assert_case(cases, "session_unknown_is_empty")


def test_the_power_button_uses_a_theme_icon() -> None:
    """El boton de la barra usa el simbolo de apagado del tema."""
    cases = run_cases()
    assert_case(cases, "power_button")


def test_the_speaker_icon_follows_the_level() -> None:
    """Los cuatro niveles del altavoz eligen su icono."""
    cases = run_cases()
    assert_case(cases, "speaker_high")
    assert_case(cases, "speaker_medium")
    assert_case(cases, "speaker_low")
    assert_case(cases, "speaker_muted")


def test_mute_wins_over_the_level() -> None:
    """Silenciado y nivel practicamente cero piden el icono de mute."""
    cases = run_cases()
    assert_case(cases, "speaker_muted")
    assert_case(cases, "speaker_silenced_by_level")
    assert_case(cases, "microphone_silenced_by_level")


def test_the_level_thresholds_are_the_same_as_before() -> None:
    """El 40 y el 75 por ciento siguen siendo los cortes de nivel."""
    cases = run_cases()
    assert_case(cases, "speaker_threshold_low_high")
    assert_case(cases, "speaker_threshold_medium_high")


def test_the_microphone_has_two_states() -> None:
    """El microfono activo y el silenciado piden iconos distintos."""
    cases = run_cases()
    assert_case(cases, "microphone_on")
    assert_case(cases, "microphone_muted")


def test_the_power_profile_uses_theme_icons() -> None:
    """Ahorro, equilibrado y rendimiento tienen su icono de tema."""
    cases = run_cases()
    assert_case(cases, "profile_saver")
    assert_case(cases, "profile_balanced")
    assert_case(cases, "profile_performance")


def test_an_unknown_profile_falls_back_to_balanced() -> None:
    """Un perfil desconocido se dibuja como equilibrado."""
    cases = run_cases()
    assert_case(cases, "profile_unknown_is_balanced")


def test_every_state_has_a_known_icon_name() -> None:
    """Ningun estado se queda vacio ni pide un nombre mal escrito."""
    cases = run_cases()
    assert_case(cases, "every_chain_is_not_empty")
    assert_case(cases, "every_chain_name_is_known")


def test_every_chain_resolves_in_every_installed_theme() -> None:
    """Cada cadena cubre los siete temas: el icono nunca desaparece."""
    cases = run_cases()
    assert_case(cases, "every_chain_resolves_in_every_theme")


def test_the_tables_are_not_shared_with_qml() -> None:
    """El QML recibe copias: no puede modificar la tabla del modulo."""
    cases = run_cases()
    assert_case(cases, "every_chain_is_a_copy")

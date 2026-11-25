"""Contrato del entorno Qt con el que arranca la shell."""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = REPOSITORY_ROOT / "scripts" / "caparazon-shell"


def test_the_launcher_exports_the_plasma_platform_theme() -> None:
    contents = LAUNCHER.read_text(encoding="utf-8")

    assert "QT_QPA_PLATFORMTHEME" in contents
    assert "${QT_QPA_PLATFORMTHEME:-kde}" in contents


def test_the_launcher_exports_it_before_exec() -> None:
    contents = LAUNCHER.read_text(encoding="utf-8")

    export = contents.index("QT_QPA_PLATFORMTHEME:-kde")
    assert export < contents.index("exec env")

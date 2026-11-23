"""Contrato Task 8: config.kdl de niri validado y con los efectos del diseño."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CONFIG = REPOSITORY_ROOT / "integration" / "niri" / "config.kdl"


def test_niri_config_validates() -> None:
    if shutil.which("niri") is None:
        pytest.skip("niri no disponible")
    result = subprocess.run(  # noqa: S603
        ["niri", "validate", "-c", str(CONFIG)],  # noqa: S607
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stderr or result.stdout


def test_niri_config_has_effects() -> None:
    contents = CONFIG.read_text(encoding="utf-8")
    assert "gaps" in contents
    assert "border" in contents
    assert "shadow" in contents
    assert "geometry-corner-radius" in contents
    assert "animations" in contents


def test_niri_config_does_not_blur_all_quickshell_layers() -> None:
    """El blur global tapa las ventanas detrás de menús y capturadores."""
    contents = CONFIG.read_text(encoding="utf-8")

    assert 'match namespace="quickshell"' not in contents
    assert "background-effect" not in contents

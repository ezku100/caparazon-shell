"""Contrato Task 8: config.kdl de niri validado y con los efectos del diseño."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CONFIG = REPOSITORY_ROOT / "integration" / "niri" / "config.kdl"
INSTALLER = REPOSITORY_ROOT / "install.sh"


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


def test_niri_config_takes_the_border_from_accent_theme() -> None:
    """El borde lo publica el motor con el acento de la shell."""
    contents = CONFIG.read_text(encoding="utf-8")

    assert 'include "config.d/25-border-accent.kdl"' in contents
    assert "open-maximized" in contents


def test_the_installer_copies_the_niri_snippets() -> None:
    """Sin copiar config.d/, el include del config quedaría roto."""
    contents = INSTALLER.read_text(encoding="utf-8")

    assert "integration/niri/config.d" in contents


def test_niri_config_does_not_blur_all_quickshell_layers() -> None:
    """El blur global tapa las ventanas detrás de menús y capturadores."""
    contents = CONFIG.read_text(encoding="utf-8")

    assert 'match namespace="quickshell"' not in contents
    assert "background-effect" not in contents


def test_the_installer_installs_the_solo_maximize_helper() -> None:
    """El helper que ensancha la columna sola queda instalado y se puede quitar."""
    contents = INSTALLER.read_text(encoding="utf-8")

    assert 'install -m755 "$REPO/integration/bin/niri-solo-maximize" "$BIN_DIR/"' in contents
    assert 'rm -f "$BIN_DIR/niri-solo-maximize"' in contents


def test_the_solo_maximize_helper_ships_with_the_shell() -> None:
    helper = REPOSITORY_ROOT / "integration" / "bin" / "niri-solo-maximize"

    assert helper.is_file()
    assert helper.read_text(encoding="utf-8").startswith("#!/usr/bin/env python3")


def test_the_niri_startup_launches_the_solo_maximize_helper() -> None:
    startup = REPOSITORY_ROOT / "integration" / "niri" / "config.d" / "50-startup.kdl"

    assert "niri-solo-maximize" in startup.read_text(encoding="utf-8")
    assert 'include "config.d/50-startup.kdl"' in CONFIG.read_text(encoding="utf-8")

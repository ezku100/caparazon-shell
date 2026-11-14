"""Launcher de la shell: la escala elegida llega a QT_SCALE_FACTOR.

La escala es una variable de entorno del proceso, así que el lanzador la lee
de ``~/.config/caparazon/scale`` y sólo deja pasar valores conocidos.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = REPOSITORY_ROOT / "scripts" / "caparazon-shell"


def launch(tmp_path: Path, scale_text: str | None) -> subprocess.CompletedProcess[str]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    stub = bin_dir / "quickshell"
    stub.write_text('#!/bin/sh\nprintf "%s|%s\\n" "$QT_SCALE_FACTOR" "$*"\n', encoding="utf-8")
    stub.chmod(0o755)

    config_dir = tmp_path / "config"
    if scale_text is not None:
        (config_dir / "caparazon").mkdir(parents=True, exist_ok=True)
        (config_dir / "caparazon" / "scale").write_text(scale_text, encoding="utf-8")

    environment = {
        "PATH": f"{bin_dir}:/usr/bin:/bin",
        "HOME": str(tmp_path),
        "XDG_CONFIG_HOME": str(config_dir),
    }
    return subprocess.run(
        [str(LAUNCHER)], env=environment, capture_output=True, text=True, check=True
    )


def test_the_launcher_forwards_the_chosen_scale(tmp_path: Path) -> None:
    result = launch(tmp_path, "1.5\n")

    assert result.stdout.startswith("1.5|")
    assert f"-p {REPOSITORY_ROOT} -d" in result.stdout


def test_the_launcher_defaults_to_one_without_a_file(tmp_path: Path) -> None:
    assert launch(tmp_path, None).stdout.startswith("1|")


def test_the_launcher_rejects_unknown_scales(tmp_path: Path) -> None:
    assert launch(tmp_path, "9\n").stdout.startswith("1|")
    assert launch(tmp_path, "grande\n").stdout.startswith("1|")


def test_the_launcher_is_executable() -> None:
    assert os.access(LAUNCHER, os.X_OK)

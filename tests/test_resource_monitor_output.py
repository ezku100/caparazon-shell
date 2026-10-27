"""La línea del muestreo lleva los seis valores que la shell consume."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY_ROOT / "modules" / "bar" / "resource-monitor.sh"


def test_the_sampler_emits_six_fields() -> None:
    """La primera línea del script tiene seis campos y ninguno es un icono."""
    bash = shutil.which("bash")
    if bash is None:
        pytest.skip("bash no disponible")
    runner = bash or "bash"
    with pytest.raises(subprocess.TimeoutExpired) as excinfo:
        _ = subprocess.run(  # noqa: S603
            [runner, str(SCRIPT)],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    stdout = excinfo.value.stdout
    assert stdout is not None
    # Al agotarse el tiempo, TimeoutExpired guarda bytes aunque se pida texto.
    first = stdout.decode().strip().splitlines()[0]
    fields = first.split()
    assert len(fields) == 6
    assert fields[5] in {"performance", "balanced", "power-saver"}

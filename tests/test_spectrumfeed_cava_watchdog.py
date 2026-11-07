"""Si cava muere, el sampler lo relanza y el espectro sigue publicando.

Regresión: `ensure_cava` sólo corría al arrancar. Al morir cava, el FIFO
daba EOF, el bucle giraba sin publicar nada y el dedup impedía que otro
sampler lo relevara: el espectro se congelaba y sólo se recuperaba al
cambiar de submenú (lo que mata y vuelve a arrancar el sampler).
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SAMPLER = REPOSITORY_ROOT / "modules" / "music" / "spectrumfeed.py"

FAKE_CAVA = """#!/usr/bin/env python3
import os, sys, time

conf = sys.argv[sys.argv.index("-p") + 1]
fifo = next(
    line.split("=", 1)[1].strip()
    for line in open(conf)
    if line.startswith("raw_target")
)
fd = os.open(fifo, os.O_WRONLY)
i = 0
while True:
    os.write(fd, bytes(((i * 13 + j) % 200) + 40 for j in range(32)))
    i += 1
    time.sleep(1 / 30)
"""

pytestmark = pytest.mark.skipif(
    shutil.which("pgrep") is None, reason="necesita pgrep"
)


def pids(pattern: str) -> list[int]:
    result = subprocess.run(
        ["pgrep", "-f", pattern], capture_output=True, text=True
    )
    return [int(line) for line in result.stdout.split()]


def wait_for(predicate, timeout: float = 10.0, step: float = 0.1):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(step)
    return None


def stop(pattern: str) -> None:
    for pid in pids(pattern):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_the_sampler_relaunches_cava_when_it_dies(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    cava = bin_dir / "cava"
    cava.write_text(FAKE_CAVA, encoding="utf-8")
    cava.chmod(0o755)

    data = tmp_path / "data"
    data.mkdir()
    waves = data / "waves.json"
    conf = data / "cava.conf"
    sampler_pattern = f"spectrumfeed.py {data}"
    cava_pattern = f"cava -p {conf}"
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")

    def published() -> int | None:
        try:
            return waves.stat().st_mtime_ns
        except FileNotFoundError:
            return None

    try:
        subprocess.run(
            [sys.executable, str(SAMPLER), str(data)],
            env=env,
            check=True,
            timeout=15,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        assert wait_for(published), "el sampler no publicó waves.json"
        assert wait_for(lambda: pids(cava_pattern)), "cava no arrancó"

        stop(cava_pattern)
        time.sleep(0.5)
        stalled = published()
        assert wait_for(lambda: published() != stalled), (
            "el sampler no relanzó cava: waves.json se quedó congelado"
        )
        assert pids(cava_pattern), "cava no volvió a correr"
    finally:
        stop(sampler_pattern)
        stop(cava_pattern)

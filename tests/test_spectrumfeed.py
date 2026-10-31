"""Contrato del sampler del espectro del modo compacto de Música.

``spectrumfeed.py`` es una adaptación del ``wavefeed.py`` del plugin de
Noctalia: arranca cava con salida raw a un FIFO y publica 32 valores en
``waves.json``. Se llamó distinto a propósito para que su ``pkill`` no mate
el sampler del plugin.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPOSITORY_ROOT / "modules" / "music" / "spectrumfeed.py"


def load_module() -> ModuleType:
    """Carga el script como módulo sin ejecutar su main."""
    spec = importlib.util.spec_from_file_location("spectrumfeed", MODULE_PATH)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_cava_config_asks_for_32_bars(tmp_path: Path) -> None:
    """El espectro tiene que tener 32 barras."""
    config = load_module().cava_config(str(tmp_path / "prueba.fifo"))

    assert "bars = 32" in config


def test_the_cava_config_writes_raw_8_bit_to_the_fifo(tmp_path: Path) -> None:
    """La salida es raw, 8 bits, mono, al FIFO indicado."""
    fifo = tmp_path / "prueba.fifo"
    config = load_module().cava_config(str(fifo))

    assert "method = raw" in config
    assert f"raw_target = {fifo}" in config
    assert "bit_format = 8bit" in config
    assert "channels = mono" in config
    assert "mono_option = average" in config


def test_the_state_files_live_in_the_datadir(tmp_path: Path) -> None:
    """Config, FIFO y waves viven juntos en el datadir pedido."""
    conf, fifo, waves = load_module().paths(str(tmp_path))

    assert conf == str(tmp_path / "cava.conf")
    assert fifo == str(tmp_path / "cava.fifo")
    assert waves == str(tmp_path / "waves.json")


def test_normalize_lifts_a_quiet_frame_to_full_scale() -> None:
    """Con el volumen bajo el pico tiene que llegar arriba."""
    frame, reference = load_module().normalize([10, 20, 5], 0.0)

    assert max(frame) == 255
    assert reference == 20


def test_normalize_keeps_the_shape_of_the_frame() -> None:
    frame, _ = load_module().normalize([10, 20, 5], 0.0)

    assert frame == [128, 255, 64]


def test_normalize_treats_silence_as_zero() -> None:
    """Sin música no se amplifica el ruido de fondo."""
    frame, reference = load_module().normalize([3, 1, 0], 200.0)

    assert frame == [0, 0, 0]
    assert reference == 0.0


def test_normalize_holds_the_reference_across_frames() -> None:
    """Un golpe fuerte mantiene la escala un momento: evita el bombeo."""
    module = load_module()
    _, reference = module.normalize([200, 100], 0.0)
    quiet, reference = module.normalize([40, 20], reference)

    assert reference > 40
    assert max(quiet) < 255

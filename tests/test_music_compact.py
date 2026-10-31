"""Contrato del modo compacto de la categoría Música.

El panel oculta letra, barra y botones, deja el álbum con el vinilo, pone un
espectro al pie y recuerda la elección. Aquí se comprueba el cableado
estático de los ficheros QML, como en ``test_music_art.py``.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MUSIC_PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "MusicPanel.qml"
MUSIC_SETTINGS = REPOSITORY_ROOT / "modules" / "music" / "MusicSettings.qml"
SPECTRUM = REPOSITORY_ROOT / "modules" / "music" / "Spectrum.qml"


def contents(path: Path) -> str:
    """Devuelve el contenido de un archivo del repositorio."""
    return path.read_text(encoding="utf-8")


def test_the_settings_file_exists() -> None:
    """El modo se recuerda en un servicio propio."""
    assert MUSIC_SETTINGS.is_file()


def test_the_settings_live_in_the_caparazon_cache() -> None:
    """El estado vive junto al resto de la caché de Caparazón."""
    settings = contents(MUSIC_SETTINGS)

    assert "/.cache/caparazon" in settings
    assert "music-panel.json" in settings


def test_the_settings_expose_and_persist_compact() -> None:
    """El servicio expone `compact`, lo lee y lo guarda."""
    settings = contents(MUSIC_SETTINGS)

    assert "property bool compact" in settings
    assert "JsonAdapter" in settings
    assert "function save(" in settings


def test_the_settings_write_atomically() -> None:
    """Se escribe a un .tmp y se renombra, como el resto del repo."""
    settings = contents(MUSIC_SETTINGS)

    assert ".tmp" in settings
    assert "mv " in settings


def test_the_spectrum_component_exists() -> None:
    """El espectro es un componente propio y reutilizable."""
    assert SPECTRUM.is_file()


def test_the_spectrum_uses_the_shared_math() -> None:
    """El dibujo no reimplementa el suavizado."""
    spectrum = contents(SPECTRUM)

    assert 'import "SpectrumMath.js" as SpectrumMath' in spectrum
    assert "SpectrumMath.nextLevels(" in spectrum


def test_the_spectrum_reads_the_waves_file() -> None:
    """El espectro lee el JSON que publica el sampler."""
    spectrum = contents(SPECTRUM)

    assert "waves.json" in spectrum
    assert "FileView" in spectrum
    assert "watchChanges: true" in spectrum


def test_the_spectrum_starts_and_stops_the_sampler() -> None:
    """El sampler sólo vive mientras el espectro está activo."""
    spectrum = contents(SPECTRUM)

    assert "spectrumfeed.py" in spectrum
    assert "spectrumfeed[.]py" in spectrum


def test_the_spectrum_follows_the_theme() -> None:
    """El degradado sale de los colores del tema."""
    spectrum = contents(SPECTRUM)

    assert "Theme.m3Primary" in spectrum
    assert "Theme.m3Tertiary" in spectrum

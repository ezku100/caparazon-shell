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


def test_the_settings_write_through_the_file_view() -> None:
    """Se guarda con `writeAdapter`: Quickshell escribe de forma atómica."""
    settings = contents(MUSIC_SETTINGS)

    assert "file.writeAdapter()" in settings
    assert "persist" not in settings


def test_the_settings_apply_the_saved_value_after_the_load() -> None:
    """Se lee con la señal `loaded`, que llega con el adapter ya relleno.

    La propiedad `loaded` se pone a true al empezar la carga asíncrona, así
    que escuchar `onLoadedChanged` devolvía el valor por defecto.
    """
    settings = contents(MUSIC_SETTINGS)

    assert "function onLoaded()" in settings
    assert "onLoadedChanged" not in settings


def test_the_panel_toggles_through_set_compact() -> None:
    """El panel usa `setCompact` para no reescribir en la carga inicial."""
    panel = contents(MUSIC_PANEL)
    settings = contents(MUSIC_SETTINGS)

    assert "function setCompact(" in settings
    assert "compactSettings.setCompact(" in panel


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


def test_the_panel_hides_the_controls_in_compact_mode() -> None:
    """En compacto desaparecen la barra de progreso y los botones."""
    panel = contents(MUSIC_PANEL)

    assert "root.compact" in panel
    assert "controlsCard" in panel
    assert "visible: !root.compact" in panel


def test_the_panel_hides_the_lyrics_in_compact_mode() -> None:
    """En compacto desaparece la letra."""
    panel = contents(MUSIC_PANEL)

    lyrics_block = panel.split("id: lyricsCard", 1)[1].split("id: lyricsList", 1)[0]
    assert "root.compact" in lyrics_block


def test_the_panel_puts_the_spectrum_at_the_bottom() -> None:
    """El espectro es el pie del panel, no va entre el álbum y el título."""
    panel = contents(MUSIC_PANEL)

    assert "Spectrum {" in panel
    assert "active: root.compact" in panel
    discs_block = panel.split("id: discs", 1)[1].split("id: lyricsCard", 1)[0]
    assert "Spectrum {" not in discs_block


def test_the_panel_has_the_compact_button() -> None:
    """El botón ⛶ alterna el modo y usa un icono del tema."""
    panel = contents(MUSIC_PANEL)

    assert "toggleCompact" in panel
    assert "view-fullscreen" in panel
    assert "window-restore" in panel
    assert "IconResolver.firstOf(" in panel


def test_the_panel_uses_the_settings_service() -> None:
    """El modo del panel sale del servicio que lo recuerda."""
    panel = contents(MUSIC_PANEL)

    assert 'import "../music"' in panel
    assert "MusicSettings {" in panel
    assert "compactSettings.compact" in panel


def test_the_panel_keeps_the_album_visible_in_compact_mode() -> None:
    """El álbum no se sustituye: sigue ahí con el vinilo."""
    panel = contents(MUSIC_PANEL)

    assert "id: discs" in panel
    assert "id: vinyl" in panel


def test_the_album_toggles_playback_on_click() -> None:
    """Un clic en el álbum pausa o reanuda, en los dos modos."""
    panel = contents(MUSIC_PANEL)

    discs_block = panel.split("id: discs", 1)[1].split("id: lyricsCard", 1)[0]
    assert "togglePlaying()" in discs_block
    assert "canTogglePlaying" in discs_block


def test_the_album_click_does_not_eat_the_wheel() -> None:
    """El clic convive con la rueda que cambia de reproductor."""
    panel = contents(MUSIC_PANEL)

    discs_block = panel.split("id: discs", 1)[1].split("id: lyricsCard", 1)[0]
    assert "WheelHandler" in discs_block

"""Contrato de la resolución de carátulas de la categoría Música.

Los navegadores (Zen, Firefox, Chromium) no mandan ``mpris:artUrl`` cuando
suenan vídeos de YouTube: sólo mandan ``xesam:url``. La lógica que traduce
esa URL en una carátula vive en ``modules/music/ArtUrls.js``; aquí se ejecuta
con node y se comprueba además el cableado del panel y del dock.
"""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HARNESS = REPOSITORY_ROOT / "tests" / "support" / "art_urls_harness.js"
ART_URLS = REPOSITORY_ROOT / "modules" / "music" / "ArtUrls.js"
MUSIC_PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "MusicPanel.qml"
MUSIC_WIDGET = REPOSITORY_ROOT / "modules" / "dock" / "MusicWidget.qml"


@dataclass(frozen=True, slots=True)
class ArtCase:
    """Resultado de un escenario de resolución de carátula."""

    ok: bool
    detail: str


def run_cases() -> dict[str, ArtCase]:
    """Ejecuta los escenarios de carátula y devuelve sus resultados."""
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

    cases: dict[str, ArtCase] = {}
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        case_id, verdict, detail = parts
        cases[case_id] = ArtCase(ok=verdict == "PASS", detail=detail)
    return cases


CASES = run_cases()


def contents(path: Path) -> str:
    """Devuelve el contenido de un archivo del repositorio."""
    return path.read_text(encoding="utf-8")


@pytest.mark.parametrize("case_id", sorted(CASES))
def test_the_art_url_contract(case_id: str) -> None:
    """Cada escenario de carátula debe cumplirse."""
    case = CASES[case_id]

    assert case.ok, case.detail


def test_the_shared_resolver_exists() -> None:
    """La lógica de carátulas vive en un módulo compartido."""
    assert ART_URLS.is_file()


def test_the_music_panel_uses_the_shared_resolver() -> None:
    """El panel de Música saca la carátula del módulo compartido."""
    panel = contents(MUSIC_PANEL)

    assert 'import "../music/ArtUrls.js" as ArtUrls' in panel
    assert "ArtUrls.artCandidates(player)" in panel


def test_the_music_panel_advances_when_an_image_fails() -> None:
    """Si una miniatura no carga, se prueba la siguiente."""
    panel = contents(MUSIC_PANEL)

    assert "root.artIndex += 1" in panel
    assert "Image.Error" in panel


def test_the_music_panel_does_not_rely_only_on_track_art_url() -> None:
    """El panel no se queda sólo con la carátula que manda el reproductor."""
    assert "player.trackArtUrl" not in contents(MUSIC_PANEL)


def test_the_dock_uses_the_shared_resolver() -> None:
    """El dock usa el mismo módulo y no duplica su lógica."""
    widget = contents(MUSIC_WIDGET)

    assert 'import "../music/ArtUrls.js" as ArtUrls' in widget
    assert "ArtUrls.artCandidates(player)" in widget
    assert "ytIdFromPage" not in widget


def test_the_music_panel_switches_player_with_the_wheel() -> None:
    """La rueda sobre el álbum cambia de reproductor."""
    panel = contents(MUSIC_PANEL)

    assert "WheelHandler" in panel
    assert "root.cyclePlayer(" in panel


def test_the_wheel_handler_is_not_inside_the_cover_image() -> None:
    """Sin carátula la imagen está oculta y no recibe la rueda.

    El handler va en el bloque del álbum, que siempre es visible.
    """
    panel = contents(MUSIC_PANEL)

    image_block = panel.split("id: coverImage", 1)[1].split("id: coverBox", 1)[0]
    assert "WheelHandler" not in image_block
    assert "WheelHandler" in panel.split("id: discs", 1)[1].split("id: vinyl", 1)[0]

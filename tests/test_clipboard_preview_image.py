"""La miniatura del portapapeles no debe abrir texto como imagen.

`Image.source` se evalúa aunque la miniatura esté oculta. Con
`source: modelData.text`, cualquier entrada del historial (HTML de una
página, una URL, una ruta `.rar`) se intentaba abrir como imagen: el log de
Quickshell se llenaba de descargas y errores de decodificación, y las
imágenes grandes se decodificaban a tamaño completo aunque el chip mida
64×64.
"""

from __future__ import annotations

import re
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
APP_MENU = REPOSITORY_ROOT / "modules" / "appmenu" / "AppMenu.qml"

GUARDED_SOURCE = re.compile(
    r"source:\s*clipDelegate\.imagePreview\s*\?\s*modelData\.text\s*:\s*\"\""
)
RAW_SOURCE = re.compile(r"source:\s*modelData\.text\s*$", re.MULTILINE)


def test_the_thumbnail_only_loads_entries_that_are_images() -> None:
    contents = APP_MENU.read_text(encoding="utf-8")

    assert GUARDED_SOURCE.search(contents), (
        "la miniatura debe condicionar `source` a `imagePreview`"
    )
    assert not RAW_SOURCE.search(contents), (
        "el texto crudo del portapapeles no puede ser `source` de la imagen"
    )


def test_the_thumbnail_decodes_at_chip_size() -> None:
    """Sin `sourceSize`, Qt decodifica la imagen a su tamaño natural."""
    contents = APP_MENU.read_text(encoding="utf-8")

    assert re.search(r"sourceSize\.width:\s*64", contents)
    assert re.search(r"sourceSize\.height:\s*64", contents)


def test_the_thumbnail_does_not_cache_decoded_images() -> None:
    contents = APP_MENU.read_text(encoding="utf-8")

    assert "cache: false" in contents
    assert "asynchronous: true" in contents


def test_the_thumbnail_only_previews_known_image_suffixes() -> None:
    contents = APP_MENU.read_text(encoding="utf-8")

    for suffix in (".png", ".jpg", ".jpeg", ".webp"):
        assert f'endsWith("{suffix}")' in contents

"""La hora de la columna vertical lleva dos dígitos siempre.

A las 9 la columna mostraba "9": al pasar a las 10 el ancho cambiaba y la
hora no quedaba alineada con los minutos.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLOCK = REPOSITORY_ROOT / "modules" / "bar" / "Clock.qml"


def test_the_vertical_hour_is_padded_to_two_digits() -> None:
    contents = CLOCK.read_text(encoding="utf-8")

    assert 'String(root.hour12).padStart(2, "0")' in contents


def test_the_horizontal_clock_keeps_its_single_digit_hour() -> None:
    """En la fila el formato "h:mm AP" no cambia."""
    contents = CLOCK.read_text(encoding="utf-8")

    assert '"h:mm AP"' in contents

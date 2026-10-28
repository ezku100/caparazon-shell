"""La paleta no debe sonararse cada segundo.

`colors.json` se publica de forma atómica y la shell lo ve con
`watchChanges`; un temporizador de 1 s es ruido permanente en el compositor.
"""

from __future__ import annotations

import re
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PALETTE = REPOSITORY_ROOT / "theme" / "MatugenPalette.qml"

TIMER_INTERVAL = re.compile(r"interval:\s*(\d+)")


def test_the_palette_watches_the_file_instead_of_polling() -> None:
    contents = PALETTE.read_text(encoding="utf-8")

    assert "watchChanges: true" in contents


def test_the_fallback_timer_is_not_faster_than_five_seconds() -> None:
    contents = PALETTE.read_text(encoding="utf-8")
    intervals = [int(match.group(1)) for match in TIMER_INTERVAL.finditer(contents)]

    assert intervals
    assert min(intervals) >= 5000

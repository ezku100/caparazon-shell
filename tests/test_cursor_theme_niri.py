from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "CursorThemePanel.qml"


def test_the_cursor_panel_reads_and_writes_through_the_cli() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert '"caparazon-wm"' in contents
    assert '"cursor-theme"' in contents
    assert '"--set"' in contents


def test_the_cursor_panel_does_not_write_configuration_files() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert ".config/niri" not in contents
    assert "FileView" not in contents


def test_the_cursor_panel_does_not_announce_a_restart() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "reinici" not in contents


def test_the_cursor_panel_shows_a_pointer_glyph_and_success_notice() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "↖" in contents
    assert "cell.active" in contents
    assert "Cursor aplicado." in contents

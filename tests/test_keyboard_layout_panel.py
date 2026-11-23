from pathlib import Path

PANEL = (
    Path(__file__).resolve().parents[1]
    / "modules"
    / "secondmenu"
    / "KeyboardLayoutPanel.qml"
)


def test_keyboard_panel_reads_and_applies_through_the_cli() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"keyboard-layout"' in contents
    assert '"--set"' in contents
    assert "root.pendingLayout" in contents
    assert "root.pendingVariant" in contents


def test_keyboard_panel_does_not_talk_to_the_system() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert ".config/niri" not in contents
    assert "niri msg" not in contents
    assert "FileView" not in contents
    assert "QtQuick.Controls" not in contents


def test_keyboard_panel_groups_languages_and_variants() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "Grid {" in contents
    assert "Repeater {" in contents
    assert "SegmentedChoice" in contents
    assert "currentLanguageOptions()" in contents
    assert "chooseLanguage(modelData" in contents or "chooseLanguage(index)" in contents
    assert "chooseVariant(key)" in contents


def test_keyboard_panel_applies_the_variant_only_when_present() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index("function applyKeyboard()")
    end = contents.index("Process {", start)
    block = contents[start:end]
    assert "root.pendingVariant.length > 0" in block
    assert "root.pendingLayout" in block
    assert "root.pendingVariant" in block


def test_keyboard_panel_has_no_nested_scroll() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "Flickable" not in contents
    assert "GridView" not in contents
    assert "implicitHeight: content.implicitHeight + 12" in contents


def test_keyboard_panel_grid_has_an_id() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index("Grid {")
    end = contents.index("Repeater {", start)
    block = contents[start:end]
    assert "id: grid" in block
    assert "width: grid.cellWidth" in contents

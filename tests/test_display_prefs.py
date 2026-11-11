from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAYOUT = REPOSITORY_ROOT / "theme" / "ShellLayout.qml"
SHELL = REPOSITORY_ROOT / "shell.qml"
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "ShellConfigPanel.qml"
TOGGLE = REPOSITORY_ROOT / "modules" / "secondmenu" / "ToggleRow.qml"


def test_the_options_live_in_display_json() -> None:
    contents = LAYOUT.read_text(encoding="utf-8")

    assert "display.json" in contents
    assert "property bool barOnSecondary: true" in contents
    assert "property bool dockOnSecondary: true" in contents


def test_the_primary_screen_comes_from_kscreen() -> None:
    """El principal es el que KDE marca (prioridad 1), no el primero."""
    contents = LAYOUT.read_text(encoding="utf-8")

    assert "kscreen-doctor" in contents
    assert "priority < best.priority" in contents
    assert "root.primaryName = best.name" in contents


def test_screens_are_filtered_by_the_option() -> None:
    contents = LAYOUT.read_text(encoding="utf-8")

    assert "function screensFor(showOnSecondary)" in contents
    assert "return [root.primaryScreen]" in contents
    assert "readonly property var barScreens: root.screensFor(root.barOnSecondary)" in contents
    assert "readonly property var dockScreens: root.screensFor(root.dockOnSecondary)" in contents


def test_the_shell_uses_the_filtered_screen_lists() -> None:
    contents = SHELL.read_text(encoding="utf-8")

    assert "model: ShellLayout.barScreens" in contents
    assert "model: ShellLayout.dockScreens" in contents


def test_the_panel_offers_both_switches() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "Barra en monitores secundarios" in contents
    assert "Dock en monitores secundarios" in contents
    assert "ShellLayout.setBarOnSecondary" in contents
    assert "ShellLayout.setDockOnSecondary" in contents


def test_the_switch_row_reacts_to_the_value() -> None:
    contents = TOGGLE.read_text(encoding="utf-8")

    assert "property bool value: false" in contents
    assert "signal toggled()" in contents
    assert "onClicked: root.toggled()" in contents

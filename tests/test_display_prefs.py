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


def test_screens_are_filtered_by_the_options() -> None:
    contents = LAYOUT.read_text(encoding="utf-8")

    assert "function screensFor(onPrimary, onSecondary)" in contents
    assert "function barShownFor(screen)" in contents
    assert "return root.barOnSecondary" in contents
    assert "root.screensFor(root.dockOnPrimary, root.dockOnSecondary)" in contents


def test_the_bar_never_disappears_completely() -> None:
    """Sin barra no hay acceso al panel: siempre queda en una pantalla."""
    contents = LAYOUT.read_text(encoding="utf-8")

    assert "readonly property bool barPrimaryCanTurnOff" in contents
    assert "if (!value && !root.barPrimaryCanTurnOff)" in contents
    assert "return !root.hasSecondaryScreen || !root.barOnSecondary" in contents


def test_the_shell_uses_the_filtered_screen_lists() -> None:
    contents = SHELL.read_text(encoding="utf-8")

    assert "model: Quickshell.screens" in contents
    assert "shown: ShellLayout.barShownFor(modelData)" in contents
    assert "model: ShellLayout.dockScreens" in contents


def test_the_panel_offers_the_four_switches() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "Barra en el monitor principal" in contents
    assert "Barra en monitores secundarios" in contents
    assert "Dock en el monitor principal" in contents
    assert "Dock en monitores secundarios" in contents
    assert "ShellLayout.setBarOnPrimary" in contents
    assert "ShellLayout.setBarOnSecondary" in contents
    assert "ShellLayout.setDockOnPrimary" in contents
    assert "ShellLayout.setDockOnSecondary" in contents


def test_the_switch_row_reacts_to_the_value() -> None:
    contents = TOGGLE.read_text(encoding="utf-8")

    assert "property bool value: false" in contents
    assert "signal toggled()" in contents
    assert "onClicked: root.toggled()" in contents
    assert "property bool available: true" in contents
    assert "enabled: root.available" in contents

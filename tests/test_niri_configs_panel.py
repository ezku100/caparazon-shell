from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "NiriConfigsPanel.qml"


def test_the_panel_follows_the_category_pattern() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "Flickable {" in contents
    assert "clip: true" in contents
    assert "contentWidth: width" in contents
    assert "contentHeight: body.implicitHeight" in contents
    assert "boundsBehavior: Flickable.StopAtBounds" in contents
    assert "interactive: contentHeight > height" in contents
    assert "id: body" in contents


def test_the_panel_has_a_category_header() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert 'text: "Niri configs"' in contents
    assert "font.weight: Font.DemiBold" in contents


def test_the_panel_has_no_theme_sections() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "readonly property var sections: [" not in contents
    assert '{ key: "iconos", label: "Iconos" }' not in contents
    assert '{ key: "cursor", label: "Cursor" }' not in contents


def test_the_panel_has_no_segmented_choice() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "SegmentedChoice" not in contents
    assert "options: root.sections" not in contents
    assert "value: root.tab" not in contents


def test_the_panel_resolves_no_section_to_a_component() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "function componentFor(key)" not in contents
    assert "return cursorComponent" not in contents
    assert "return iconComponent" not in contents


def test_the_panel_has_no_default_tab() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert 'property string tab: "iconos"' not in contents


def test_the_panel_mounts_no_theme_panel() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "IconThemePanel" not in contents
    assert "CursorThemePanel" not in contents


def test_the_wrapper_has_no_custom_tabs() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "id: iconTab" not in contents
    assert "id: cursorTab" not in contents


def test_the_wrapper_does_not_talk_to_the_system() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "Process" not in contents
    assert "caparazon-wm" not in contents
    assert ".config/niri" not in contents


def test_the_panel_mounts_monitors_as_a_separate_section() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "id: monitorsHost" in contents
    assert "sourceComponent: monitorComponent" in contents
    assert 'text: "Monitores"' in contents
    assert contents.index("id: monitorsHost") < contents.index("id: keyboardHost")


def test_the_panel_sizes_its_sections_to_their_content() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "id: monitorsLoader" in contents
    assert (
        "height: monitorsLoader.item ? monitorsLoader.item.implicitHeight"
        in contents
    )
    assert "id: keyboardLoader" in contents
    assert (
        "height: keyboardLoader.item ? keyboardLoader.item.implicitHeight"
        in contents
    )
    assert "Math.max(280, root.height - 110)" not in contents
    assert "height: 360" not in contents


def test_the_wrapper_mounts_the_monitors_panel() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "MonitorsPanel" in contents


def test_the_panel_orders_monitors_and_keyboard() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "id: monitorsHost" in contents
    assert "id: keyboardHost" in contents
    assert contents.index("id: monitorsHost") < contents.index("id: keyboardHost")


def test_the_panel_mounts_the_keyboard_panel() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "KeyboardLayoutPanel" in contents
    assert "id: keyboardComponent" in contents
    assert "sourceComponent: keyboardComponent" in contents


def test_the_theme_is_not_part_of_the_panel() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '{ key: "tema", label: "Tema" }' not in contents
    assert 'if (key === "tema")' not in contents
    assert "return appThemeComponent" not in contents


def test_the_manual_app_theme_panel_is_gone() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "AppThemePanel" not in contents
    assert "appThemeComponent" not in contents
    assert "id: themeHost" not in contents
    assert "id: themeLoader" not in contents


def test_the_panel_leaves_no_separator_line_at_the_end() -> None:
    """El panel no usa líneas separadoras: ninguna otra categoría las lleva."""
    contents = PANEL.read_text(encoding="utf-8")

    assert "Theme.m3OutlineVariant" not in contents

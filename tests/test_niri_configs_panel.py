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


def test_the_panel_registers_its_sections() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "readonly property var sections: [" in contents
    assert '{ key: "iconos", label: "Iconos" }' in contents
    assert '{ key: "cursor", label: "Cursor" }' in contents
    assert '{ key: "monitores", label: "Monitores" }' not in contents


def test_the_panel_uses_the_shared_segmented_choice() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "SegmentedChoice" in contents
    assert "options: root.sections" in contents
    assert "value: root.tab" in contents
    assert "onPicked: (key) => root.tab = key" in contents


def test_the_panel_resolves_each_section_to_a_component() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "function componentFor(key)" in contents
    assert 'if (key === "cursor")' in contents
    assert "return cursorComponent" in contents
    assert "return iconComponent" in contents
    assert "sourceComponent: root.componentFor(root.tab)" in contents
    assert 'if (key === "monitores")' not in contents


def test_the_wrapper_defaults_to_the_icon_tab() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert 'property string tab: "iconos"' in contents


def test_the_wrapper_mounts_both_panels() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "IconThemePanel" in contents
    assert "CursorThemePanel" in contents


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
    assert "Theme.m3OutlineVariant" in contents
    assert contents.index("id: monitorsHost") < contents.index("id: panelHost")


def test_the_panel_sizes_its_sections_to_their_content() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "id: panelLoader" in contents
    assert "height: panelLoader.item ? panelLoader.item.implicitHeight" in contents
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


def test_the_panel_orders_monitors_keyboard_and_themes() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "id: monitorsHost" in contents
    assert "id: keyboardHost" in contents
    assert "id: panelHost" in contents
    assert contents.index("id: monitorsHost") < contents.index("id: keyboardHost")
    assert contents.index("id: keyboardHost") < contents.index("id: panelHost")


def test_the_panel_mounts_the_keyboard_panel() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "KeyboardLayoutPanel" in contents
    assert "id: keyboardComponent" in contents
    assert "sourceComponent: keyboardComponent" in contents

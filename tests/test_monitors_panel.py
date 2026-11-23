from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "MonitorsPanel.qml"


def test_monitors_panel_reads_and_applies_through_the_cli() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '"caparazon-wm"' in contents
    assert '"monitors"' in contents
    assert '"--apply"' in contents
    assert "root.pendingJson" in contents
    assert "JSON.stringify" in contents


def test_monitors_panel_does_not_talk_to_the_system() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert ".config/niri" not in contents
    assert "niri msg" not in contents
    assert "FileView" not in contents
    assert "QtQuick.Controls" not in contents


def test_monitors_panel_exposes_all_controls() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert '"Monitores"' in contents
    assert '"Principal"' in contents
    assert '"Resolución y tasa"' in contents
    assert '"Rotación"' in contents
    assert '"Posición"' in contents
    assert '"Aplicar"' in contents
    assert "SegmentedChoice" in contents
    assert "Column" in contents
    assert "Flickable" not in contents
    assert "implicitHeight: content.implicitHeight" in contents
    assert "errorMessage" in contents
    assert "noticeMessage" in contents


def test_monitors_panel_refreshes_the_shell_primary_after_apply() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index("if (exitCode === 0)")
    end = contents.index("} else if", start)
    block = contents[start:end]

    assert "load.running = true" in block
    assert "ShellLayout.refreshPrimary()" in block
    assert (
        block.index("load.running = true")
        < block.index("ShellLayout.refreshPrimary()")
    )


def test_monitors_panel_keeps_selected_monitor_after_state_reload() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index("function applyState(payload) {")
    end = contents.index("function selectedOutput()", start)
    block = contents[start:end]

    assert "const previousSelection = root.selectedName" in block
    expected = (
        "root.selectedName = next[previousSelection] ? previousSelection : "
        "root.primaryName"
    )
    assert expected in block
    assert block.index("root.selectedName = next[previousSelection]") < block.index(
        "root.syncPositionInputs()"
    )


def test_monitors_panel_marks_selection_independently_from_primary() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index(
        "delegate: Rectangle {", contents.index("model: root.outputs")
    )
    end = contents.index("text: root.selectedOutput() ?", start)
    block = contents[start:end]

    assert "border.width: active ? 2" in block
    assert "border.color: active ? Theme.m3Primary" in block
    assert "visible: primary" in block
    assert "Theme.m3SurfaceContainerHighest" in block


def test_monitors_panel_marks_the_selected_resolution() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index(
        "model: root.selectedOutput() ? root.selectedOutput().modes : []"
    )
    end = contents.index('text: "Rotación"', start)
    block = contents[start:end]

    assert "border.width: active ? 2" in block
    assert "font.weight: active ? Font.DemiBold" in block
    assert "Theme.m3SurfaceContainerHighest" in block


def test_monitors_panel_commits_position_before_serializing() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index("function prepareApply()")
    end = contents.index("Process {", start)
    block = contents[start:end]

    assert 'commitPosition("x", xInput)' in block
    assert 'commitPosition("y", yInput)' in block
    assert block.index('commitPosition("x", xInput)') < block.index("JSON.stringify")


def test_monitors_panel_syncs_position_fields_on_state_and_selection() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    state_start = contents.index("function applyState(payload) {")
    state_end = contents.index("function selectedOutput()", state_start)
    state_block = contents[state_start:state_end]

    select_start = contents.index("root.selectedName = modelData.name;")
    select_end = contents.index("}\n                        }", select_start)
    select_block = contents[select_start:select_end]

    assert "function syncPositionInputs()" in contents
    assert "syncPositionInputs()" in state_block
    assert "syncPositionInputs()" in select_block


def test_resolutions_are_collapsed_by_default() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "property bool resolutionsOpen: false" in contents
    assert "function selectedModeLabel()" in contents
    assert "root.resolutionsOpen = !root.resolutionsOpen" in contents
    assert 'root.resolutionsOpen ? "▴" : "▾"' in contents
    assert "visible: root.resolutionsOpen" in contents


def test_resolutions_close_after_picking_a_mode() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    start = contents.index(
        "model: root.selectedOutput() ? root.selectedOutput().modes : []"
    )
    end = contents.index('text: "Rotación"', start)
    block = contents[start:end]
    assert "root.patchSelected({ mode: modelData.label })" in block
    assert "root.resolutionsOpen = false" in block


def test_monitors_panel_has_no_nested_scroll() -> None:
    contents = PANEL.read_text(encoding="utf-8")
    assert "Flickable" not in contents
    assert "GridView" not in contents
    assert "interactive" not in contents

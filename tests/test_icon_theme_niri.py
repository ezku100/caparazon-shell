"""Contrato QML: los iconos del sistema y del menú sólo se ajustan en niri.

En Plasma el tema de iconos lo pone KDE y lo vigila IconThemeWatcher. En niri
no hay nadie que lo configure: la shell necesita saber en qué compositor está
para ofrecer la categoría "Niri configs", y necesita una forma de escribir el tema
sin tocar ficheros de configuración desde el QML.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
COMPOSITOR_SERVICE = REPOSITORY_ROOT / "modules" / "icons" / "CompositorService.qml"
ICONS_QMLDIR = REPOSITORY_ROOT / "modules" / "icons" / "qmldir"
SECOND_MENU = REPOSITORY_ROOT / "modules" / "secondmenu" / "SecondMenu.qml"
WATCHER = REPOSITORY_ROOT / "modules" / "icons" / "IconThemeWatcher.qml"
ICON_RESOLVER = REPOSITORY_ROOT / "modules" / "icons" / "IconResolver.qml"


def test_the_compositor_service_asks_the_cli() -> None:
    contents = COMPOSITOR_SERVICE.read_text(encoding="utf-8")

    assert '"caparazon-wm"' in contents
    assert '"detect"' in contents


def test_the_compositor_service_is_a_singleton() -> None:
    contents = ICONS_QMLDIR.read_text(encoding="utf-8")

    assert "singleton CompositorService 1.0 CompositorService.qml" in contents


def test_the_compositor_service_exposes_the_niri_flag() -> None:
    contents = COMPOSITOR_SERVICE.read_text(encoding="utf-8")

    assert "readonly property string compositor" in contents
    assert "readonly property bool niri" in contents
    assert '"niri"' in contents


def test_the_niri_configs_panel_has_no_theme_panels() -> None:
    panel = REPOSITORY_ROOT / "modules" / "secondmenu" / "NiriConfigsPanel.qml"
    contents = panel.read_text(encoding="utf-8")

    assert "IconThemePanel" not in contents
    assert "CursorThemePanel" not in contents


def test_the_icon_category_only_shows_on_niri() -> None:
    contents = SECOND_MENU.read_text(encoding="utf-8")

    assert "CompositorService.niri" in contents
    assert '"niri-configs"' in contents
    assert '"Niri configs"' in contents
    assert '"iconos"' not in contents


def test_the_niri_configs_category_mounts_the_tabs_panel() -> None:
    contents = SECOND_MENU.read_text(encoding="utf-8")

    assert "NiriConfigsPanel" in contents
    assert 'root.category === "niri-configs"' in contents


def test_the_watcher_no_longer_watches_the_default_icon_theme_file() -> None:
    contents = WATCHER.read_text(encoding="utf-8")

    assert ".icons/default" not in contents


def test_the_watcher_reuses_the_restart_path() -> None:
    contents = WATCHER.read_text(encoding="utf-8")

    assert "requestRestart" in contents


def test_the_resolver_asks_the_cli_for_the_active_theme() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert '"caparazon-wm"' in contents
    assert '"icon-theme"' in contents


def test_the_resolver_indexes_the_directories_of_the_active_theme() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert "iconTheme" in contents
    assert "userIconRoots" in contents


def test_on_niri_the_resolver_uses_its_own_index_first() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert "CompositorService.niri" in contents


def test_the_resolver_keeps_the_best_variant_of_each_icon() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert "iconRank" in contents


def test_the_resolver_receives_the_theme_search_order_from_the_cli() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert "payload.search" in contents
    assert "themeSearchOrder" in contents
    assert "root.themeSearchOrder" in contents


def test_the_resolver_indexes_the_inherited_themes() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    roots_block = contents.split("readonly property var themeIconRoots", 1)[1]
    roots_block = roots_block.split("Component.onCompleted", 1)[0]
    assert "root.themeSearchOrder" in roots_block


def test_the_resolver_ranks_by_the_theme_search_order() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert "IconNames.iconRank(path, root.themeSearchOrder)" in contents


def test_the_resolver_scans_nested_symbolic_icon_directories() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert 'depth=4; d="${d#deep:}"' in contents


def test_the_resolver_indexes_files_and_symlinks() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert "-type f -o -type l" in contents


def test_on_niri_the_resolver_only_uses_the_index_for_names() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert "function indexedByName(name)" in contents

    by_name = contents.split("function byName(name) {", 1)[1]
    by_name = by_name.split("function themed(names)", 1)[0]
    assert by_name.index("indexedByName") < by_name.index("Quickshell.iconPath")

    source = contents.split("function source(name, fallback) {", 1)[1]
    assert source.index("indexedByName") < source.index("Quickshell.iconPath")


def test_the_resolver_watches_the_file_that_holds_the_theme() -> None:
    contents = ICON_RESOLVER.read_text(encoding="utf-8")

    assert "40-environment" in contents
    assert contents.count("watchChanges: true") >= 2

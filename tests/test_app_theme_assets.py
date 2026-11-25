import re

from tests.test_caparazon_wm import REPOSITORY_ROOT


def test_app_theme_template_and_descriptor_files_exist() -> None:
    root = REPOSITORY_ROOT / "integration" / "theme" / "app-theme"
    for name in (
        "gtk3-colors.css.tmpl",
        "gtk4-colors.css.tmpl",
        "qt5ct-colors.conf.tmpl",
        "qt6ct-colors.conf.tmpl",
        "kvantum.kvconfig.tmpl",
        "kvantum.svg.tmpl",
    ):
        assert (root / "templates" / name).is_file()
    for name in (
        "caparazon-app-gtk3.toml",
        "caparazon-app-gtk4.toml",
        "caparazon-app-qt5ct.toml",
        "caparazon-app-qt6ct.toml",
        "caparazon-app-kvantum-config.toml",
        "caparazon-app-kvantum-svg.toml",
    ):
        assert (root / "templates.d" / name).is_file()


def test_app_theme_descriptors_match_expected_outputs() -> None:
    descriptors = (
        REPOSITORY_ROOT / "integration" / "theme" / "app-theme" / "templates.d"
    ).glob("*.toml")
    parsed: dict[str, str] = {}
    for path in descriptors:
        values: dict[str, str] = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip()
        parsed[values["name"].strip(' "')] = values["output_path"].strip(' "')
    assert parsed == {
        "caparazon-app-gtk3": "~/.config/gtk-3.0/colors.css",
        "caparazon-app-gtk4": "~/.config/gtk-4.0/colors.css",
        "caparazon-app-qt5ct": "~/.config/qt5ct/colors/matugen.conf",
        "caparazon-app-qt6ct": "~/.config/qt6ct/colors/matugen.conf",
        "caparazon-app-kvantum-config": (
            "~/.config/Kvantum/matugen/matugen.kvconfig"
        ),
        "caparazon-app-kvantum-svg": "~/.config/Kvantum/matugen/matugen.svg",
    }


def test_app_theme_templates_use_placeholders() -> None:
    root = REPOSITORY_ROOT / "integration" / "theme" / "app-theme" / "templates"
    for template in root.glob("*.tmpl"):
        text = template.read_text(encoding="utf-8")
        assert re.search(r"\{\{colors\.[a-z_]+\.dark\.hex\}\}", text)
        assert re.search(r"#[0-9a-fA-F]{6}", text) is None


def test_readme_documents_manual_app_theme() -> None:
    text = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
    assert "Tema de aplicaciones en niri" in text
    assert "Niri configs" in text
    assert "GTK" in text
    assert "Qt" in text


def test_readme_documents_cli_contract() -> None:
    text = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
    assert "caparazon-wm app-theme" in text
    assert "caparazon-wm app-theme --set" in text


def test_readme_documents_future_watcher() -> None:
    text = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
    assert "vigilante de wallpaper" in text
    assert "mismo comando" in text

"""Contrato de la integración de Caparazón con el motor accent-theme."""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import tomllib
from pathlib import Path
from typing import TYPE_CHECKING, cast

import pytest

if TYPE_CHECKING:
    from collections.abc import Mapping

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
THEME_DIR = REPOSITORY_ROOT / "integration" / "theme"
TEMPLATE_FILE = THEME_DIR / "quickshell-matugen.json"
DESCRIPTOR_FILE = THEME_DIR / "accent-theme.toml"
TOKENS_FILE = THEME_DIR / "required-tokens.txt"
INSTALLER = REPOSITORY_ROOT / "install.sh"
PALETTE_QML = REPOSITORY_ROOT / "theme" / "MatugenPalette.qml"
ENGINE_REPOSITORY = "https://github.com/ezku100/accent-theme.git"
ADAPTER_PROPERTY_PATTERN = re.compile(r"^\s+property string (\w+):", re.MULTILINE)

FAKE_ENGINE_INSTALLER = """#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-instalar}"
MARKER="$HOME/.local/share/accent-theme/fake-engine-marker"
case "$ACTION" in
    instalar)
        mkdir -p "$HOME/.local/bin" "$HOME/.local/share/accent-theme"
        cp "$SOURCE/accent-theme" "$HOME/.local/bin/accent-theme"
        chmod 0755 "$HOME/.local/bin/accent-theme"
        printf 'instalado\\n' > "$MARKER"
        ;;
    desinstalar)
        rm -f "$HOME/.local/bin/accent-theme"
        printf 'desinstalado\\n' > "$MARKER"
        ;;
    *)
        exit 2
        ;;
esac
"""

FAKE_ENGINE_CLI = """#!/usr/bin/env python3
import json
import os
import shutil
import sys
import tomllib
from pathlib import Path

HOME = Path(os.environ["HOME"])
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
REGISTRY = CONFIG / "accent-theme"


def register(app, descriptor):
    path = Path(descriptor)
    values = tomllib.loads(path.read_text(encoding="utf-8"))
    template_name = Path(values["input_path"]).name
    source = path.parent / template_name
    installed = REGISTRY / "templates" / app / template_name
    installed.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, installed)
    output = Path(os.path.expanduser(values["output_path"]))
    descriptor_dir = REGISTRY / "templates.d"
    descriptor_dir.mkdir(parents=True, exist_ok=True)
    (descriptor_dir / f"{app}.toml").write_text(
        "name = " + json.dumps(values["name"]) + "\\n"
        + "input_path = " + json.dumps(str(installed)) + "\\n"
        + "output_path = " + json.dumps(str(output)) + "\\n",
        encoding="utf-8",
    )


def generate():
    for descriptor in sorted((REGISTRY / "templates.d").glob("*.toml")):
        values = tomllib.loads(descriptor.read_text(encoding="utf-8"))
        template = Path(values["input_path"])
        output = Path(os.path.expanduser(values["output_path"]))
        output.parent.mkdir(parents=True, exist_ok=True)
        try:
            payload = json.loads(template.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            output.write_text("generado\\n", encoding="utf-8")
            continue
        rendered = {key: "#112233" for key in payload}
        output.write_text(json.dumps(rendered, indent=2) + "\\n", encoding="utf-8")


def main(argv):
    if argv[0] == "register":
        register(argv[2], argv[4])
        return 0
    if argv[0] == "generate":
        generate()
        return 0
    return 2


raise SystemExit(main(sys.argv[1:]))
"""


def run_git(repository: Path, *arguments: str) -> None:
    """Ejecuta git en el repositorio indicado."""
    git = shutil.which("git") or "git"
    _ = subprocess.run(  # noqa: S603
        [git, "-C", str(repository), *arguments],
        check=True,
    )


def make_fake_engine(tmp_path: Path) -> Path:
    """Crea un repositorio Git local que imita al motor accent-theme."""
    source = tmp_path / "engine"
    source.mkdir()
    installer = source / "install.sh"
    _ = installer.write_text(FAKE_ENGINE_INSTALLER, encoding="utf-8")
    installer.chmod(installer.stat().st_mode | stat.S_IXUSR)
    cli = source / "accent-theme"
    _ = cli.write_text(FAKE_ENGINE_CLI, encoding="utf-8")
    cli.chmod(cli.stat().st_mode | stat.S_IXUSR)
    git = shutil.which("git") or "git"
    _ = subprocess.run([git, "init", "--quiet", str(source)], check=True)  # noqa: S603
    run_git(source, "add", "-A")
    run_git(
        source,
        "-c",
        "user.email=contrato@accent-theme.test",
        "-c",
        "user.name=Contrato",
        "commit",
        "--quiet",
        "-m",
        "motor falso",
    )
    return source


def isolated_environment(
    tmp_path: Path,
    *,
    engine_repository: Path,
) -> dict[str, str]:
    """Prepara un HOME aislado con el motor local como repositorio remoto."""
    home = tmp_path / "home"
    home.mkdir()
    return {
        "HOME": str(home),
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_RUNTIME_DIR": str(tmp_path / "runtime"),
        "ACCENT_THEME_REPO": str(engine_repository),
    }


def run_installer(
    action: str,
    environ: Mapping[str, str],
) -> subprocess.CompletedProcess[str]:
    """Ejecuta el instalador de Caparazón con la acción indicada."""
    return subprocess.run(  # noqa: S603
        [str(INSTALLER), action],
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
        env=dict(environ),
    )


def test_installer_does_not_duplicate_an_existing_shell(tmp_path: Path) -> None:
    if shutil.which("git") is None:
        pytest.skip("git no disponible")
    engine = make_fake_engine(tmp_path)
    environ = isolated_environment(tmp_path, engine_repository=engine)
    home = tmp_path / "home"
    existing = home / "dotfiles" / "quickshell" / "caparazon"
    _ = existing.mkdir(parents=True)
    _ = (existing / "shell.qml").write_text(
        "// shell de dotfiles\n",
        encoding="utf-8",
    )
    autostart = home / ".config" / "autostart" / "caparazon.desktop"
    _ = autostart.parent.mkdir(parents=True)
    _ = autostart.write_text(
        f"[Desktop Entry]\nExec=quickshell -p {existing} -d\n",
        encoding="utf-8",
    )

    result = run_installer("instalar", environ)

    assert result.returncode == 0, result.stderr
    assert (
        existing / "shell.qml"
    ).read_text(encoding="utf-8") == "// shell de dotfiles\n"
    assert not (home / ".config" / "quickshell" / "caparazon").exists()
    assert str(existing) in autostart.read_text(encoding="utf-8")


def test_template_publishes_every_required_token() -> None:
    template = cast(
        "dict[str, str]",
        json.loads(TEMPLATE_FILE.read_text(encoding="utf-8")),
    )
    tokens = TOKENS_FILE.read_text(encoding="utf-8").split()

    assert set(template) == set(tokens)
    for value in template.values():
        assert value.startswith("{{colors.")
        assert value.endswith(".dark.hex}}")


def test_descriptor_registers_the_caparazon_palette() -> None:
    values = cast(
        "dict[str, str]",
        tomllib.loads(DESCRIPTOR_FILE.read_text(encoding="utf-8")),
    )

    assert values["name"] == "caparazon-shell-matugen"
    assert values["input_path"].endswith(
        "templates/caparazon-shell/quickshell-matugen.json",
    )
    assert values["output_path"] == "~/.cache/caparazon/colors.json"


def test_qml_reads_exactly_the_contract_tokens() -> None:
    contents = PALETTE_QML.read_text(encoding="utf-8")
    adapter = set(ADAPTER_PROPERTY_PATTERN.findall(contents))
    tokens = set(TOKENS_FILE.read_text(encoding="utf-8").split())

    assert adapter == tokens


def test_installer_bootstraps_the_engine_repository() -> None:
    contents = INSTALLER.read_text(encoding="utf-8")

    assert ENGINE_REPOSITORY in contents
    assert "accent-theme/source" in contents
    assert "--app caparazon-shell" in contents


def test_installer_requires_the_theme_dependencies() -> None:
    contents = INSTALLER.read_text(encoding="utf-8")

    for dependency in ("matugen", "inotifywait", "flock", "kreadconfig6"):
        assert dependency in contents
    assert "apt install" in contents


def test_installer_validates_the_generated_palette() -> None:
    contents = INSTALLER.read_text(encoding="utf-8")

    assert "required-tokens.txt" in contents
    assert "caparazon/colors.json" in contents


def test_palette_read_errors_are_visible() -> None:
    contents = PALETTE_QML.read_text(encoding="utf-8")

    assert "printErrors: true" in contents
    assert 'property string surface: "#141218"' in contents


def test_isolated_install_registers_the_palette(tmp_path: Path) -> None:
    if shutil.which("git") is None:
        pytest.skip("git no disponible")
    engine = make_fake_engine(tmp_path)
    environ = isolated_environment(tmp_path, engine_repository=engine)

    result = run_installer("instalar", environ)

    home = tmp_path / "home"
    assert result.returncode == 0, result.stderr
    palette = home / ".cache" / "caparazon" / "colors.json"
    assert palette.is_file()
    payload = cast(
        "dict[str, str]",
        json.loads(palette.read_text(encoding="utf-8")),
    )
    tokens = TOKENS_FILE.read_text(encoding="utf-8").split()
    assert set(payload) == set(tokens)
    assert (
        home / ".config" / "accent-theme" / "templates.d" / "caparazon-shell.toml"
    ).is_file()
    assert (
        home / ".local" / "share" / "accent-theme" / "source" / "install.sh"
    ).is_file()


def test_isolated_uninstall_removes_the_registration(tmp_path: Path) -> None:
    if shutil.which("git") is None:
        pytest.skip("git no disponible")
    engine = make_fake_engine(tmp_path)
    environ = isolated_environment(tmp_path, engine_repository=engine)
    _ = run_installer("instalar", environ)

    result = run_installer("desinstalar", environ)

    home = tmp_path / "home"
    assert result.returncode == 0, result.stderr
    assert not (
        home / ".config" / "accent-theme" / "templates.d" / "caparazon-shell.toml"
    ).exists()
    assert not (home / ".cache" / "caparazon" / "colors.json").exists()
    marker = home / ".local" / "share" / "accent-theme" / "fake-engine-marker"
    assert marker.read_text(encoding="utf-8").strip() == "desinstalado"

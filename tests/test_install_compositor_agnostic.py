"""Contrato: install.sh funciona sin KDE (niri) y sin niri (Plasma)."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

try:  # El motor falso del contrato del tema vive en otro test del mismo dir.
    from test_theme_install_contract import make_fake_engine
except ImportError:  # pragma: no cover - si pytest no inserta tests/ en sys.path
    make_fake_engine = None

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
INSTALLER = REPOSITORY_ROOT / "install.sh"
AUTOSTART_TEMPLATE = (
    REPOSITORY_ROOT / "integration" / "autostart" / "caparazon.desktop.in"
)
NIRI_CONFIG = REPOSITORY_ROOT / "integration" / "niri" / "config.kdl"


def isolated_environment(tmp_path: Path, *, desktop: str) -> dict[str, str]:
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    return {
        "HOME": str(home),
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_RUNTIME_DIR": str(tmp_path / "runtime"),
        "XDG_CURRENT_DESKTOP": desktop,
        "GIT_TERMINAL_PROMPT": "0",
        # Si el instalador intentase clonar el motor, fallaría aquí de forma
        # local en vez de tocar la red.
        "ACCENT_THEME_REPO": str(tmp_path / "engine-fake"),
    }


def run_installer(
    environ: dict[str, str],
    *,
    answers: str = "",
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603
        [str(INSTALLER), "instalar"],
        input=answers,
        capture_output=True,
        text=True,
        env=environ,
        timeout=300,
        check=False,
    )


def test_the_autostart_entry_is_not_restricted_to_kde() -> None:
    contents = AUTOSTART_TEMPLATE.read_text(encoding="utf-8")
    assert "OnlyShowIn=KDE" not in contents


def test_the_installer_asks_before_copying_the_niri_dotfile(tmp_path: Path) -> None:
    if shutil.which("bash") is None:
        pytest.skip("bash no disponible")
    environ = isolated_environment(tmp_path, desktop="niri")

    result = run_installer(environ, answers="n\n")

    assert result.returncode == 0, result.stderr
    assert "niri" in result.stdout.lower()
    assert not (tmp_path / "home" / ".config" / "niri" / "config.kdl").exists()


def test_the_installer_copies_the_niri_dotfile_when_approved(tmp_path: Path) -> None:
    if shutil.which("bash") is None:
        pytest.skip("bash no disponible")
    environ = isolated_environment(tmp_path, desktop="niri")

    result = run_installer(environ, answers="y\n")

    assert result.returncode == 0, result.stderr
    copied = tmp_path / "home" / ".config" / "niri" / "config.kdl"
    assert copied.is_file()
    assert copied.read_text(encoding="utf-8") == NIRI_CONFIG.read_text(encoding="utf-8")


def test_the_installer_works_on_niri_without_kde_tools(tmp_path: Path) -> None:
    if shutil.which("bash") is None:
        pytest.skip("bash no disponible")
    environ = isolated_environment(tmp_path, desktop="niri")

    result = run_installer(environ, answers="y\n")

    assert result.returncode == 0, result.stderr
    home = tmp_path / "home"
    # La shell y el puente se instalan igual.
    assert (home / ".config" / "quickshell" / "caparazon" / "shell.qml").is_file()
    assert (home / ".local" / "bin" / "caparazon-wm").is_file()
    assert (home / ".local" / "bin" / "caparazon-shell-ipc").is_file()
    # El arranque automático no está limitado a KDE.
    autostart = (home / ".config" / "autostart" / "caparazon.desktop").read_text(
        encoding="utf-8",
    )
    assert "OnlyShowIn=KDE" not in autostart
    # Y no se tocan las piezas exclusivas de Plasma.
    assert not (home / ".config" / "kglobalshortcutsrc").exists()
    assert not (home / ".local" / "share" / "accent-theme").exists()


def test_the_installer_works_on_plasma_without_niri(tmp_path: Path) -> None:
    if shutil.which("bash") is None:
        pytest.skip("bash no disponible")
    engine_factory = make_fake_engine
    assert engine_factory is not None, "falta el motor falso del contrato del tema"
    engine = engine_factory(tmp_path)
    environ = isolated_environment(tmp_path, desktop="KDE")
    environ["ACCENT_THEME_REPO"] = str(engine)

    result = run_installer(environ, answers="y\n")

    assert result.returncode == 0, result.stderr
    home = tmp_path / "home"
    assert (home / ".config" / "quickshell" / "caparazon" / "shell.qml").is_file()
    # En Plasma el atajo global sigue siendo el de KDE.
    assert (home / ".config" / "kglobalshortcutsrc").is_file()
    # El dotfile de niri también se ofrece (por si se instala niri después).
    assert (home / ".config" / "niri" / "config.kdl").is_file()


def test_the_installer_warns_when_niri_has_no_power_profiles_daemon(
    tmp_path: Path,
) -> None:
    if shutil.which("bash") is None:
        pytest.skip("bash no disponible")
    if shutil.which("powerprofilesctl") is not None:
        pytest.skip("power-profiles-daemon ya está instalado: no hay aviso que esperar")
    environ = isolated_environment(tmp_path, desktop="niri")

    result = run_installer(environ, answers="y\n")

    assert result.returncode == 0, result.stderr
    assert "power-profiles-daemon" in result.stdout

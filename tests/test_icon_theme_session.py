"""Contrato del arranque session-aware del tema de iconos.

En Plasma el tema lo pone KDE y Quickshell no debe forzar ningún override.
En niri la shell no hereda el entorno del compositor desde systemd, así que
el launcher debe pedirle el tema al CLI y exportarlo antes de arrancar.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
LAUNCHER_SOURCE = REPOSITORY_ROOT / "scripts" / "caparazon-shell"
AUTOSTART_TEMPLATE = (
    REPOSITORY_ROOT / "integration" / "autostart" / "caparazon.desktop.in"
)


def _install_fake_commands(root: Path) -> Path:
    bin_dir = root / "bin"
    bin_dir.mkdir(parents=True)

    cli = bin_dir / "caparazon-wm"
    cli.write_text(
        """#!/usr/bin/env bash
case "${1:-}" in
    detect) printf '%s\\n' "$FAKE_COMPOSITOR" ;;
    icon-theme) printf '%s\\n' "$FAKE_THEME_JSON" ;;
esac
""",
        encoding="utf-8",
    )
    cli.chmod(0o755)

    quickshell = bin_dir / "quickshell"
    quickshell.write_text(
        '#!/usr/bin/env bash\nenv > "$FAKE_ENV_FILE"\n',
        encoding="utf-8",
    )
    quickshell.chmod(0o755)
    return bin_dir


def _run_launcher(
    tmp_path: Path,
    *,
    compositor: str,
    theme_json: str,
    inherited_theme: str | None = None,
    runner: str | None = None,
) -> dict[str, str]:
    repo = tmp_path / "repo"
    launcher = repo / "scripts" / "caparazon-shell"
    launcher.parent.mkdir(parents=True)
    shutil.copy2(LAUNCHER_SOURCE, launcher)
    launcher.chmod(0o755)

    bin_dir = _install_fake_commands(tmp_path)
    home = tmp_path / "home"
    scale_dir = home / ".config" / "caparazon"
    scale_dir.mkdir(parents=True)
    (scale_dir / "scale.env").write_text("QT_SCALE_FACTOR=0.9\n", encoding="utf-8")

    env_file = tmp_path / "child.env"
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["XDG_CONFIG_HOME"] = str(home / ".config")
    env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '/usr/bin:/bin')}"
    env["FAKE_COMPOSITOR"] = compositor
    env["FAKE_THEME_JSON"] = theme_json
    env["FAKE_ENV_FILE"] = str(env_file)
    env.pop("QS_ICON_THEME", None)
    env.pop("CAPARAZON_ICON_THEME", None)
    if inherited_theme is not None:
        env["QS_ICON_THEME"] = inherited_theme
        env["CAPARAZON_ICON_THEME"] = inherited_theme

    command = [runner, str(launcher)] if runner is not None else [str(launcher)]
    result = subprocess.run(  # noqa: S603
        command,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return dict(
        line.split("=", 1)
        for line in env_file.read_text(encoding="utf-8").splitlines()
        if "=" in line
    )


def test_the_autostart_template_has_no_hardcoded_icon_theme() -> None:
    contents = AUTOSTART_TEMPLATE.read_text(encoding="utf-8")

    assert "QS_ICON_THEME" not in contents
    assert "CAPARAZON_ICON_THEME" not in contents


def test_the_autostart_template_uses_the_launcher() -> None:
    contents = AUTOSTART_TEMPLATE.read_text(encoding="utf-8")

    assert "Exec=@SHELL_PATH@/scripts/caparazon-shell" in contents
    assert "quickshell -p" not in contents


def test_kde_launcher_does_not_force_an_icon_theme(tmp_path: Path) -> None:
    child = _run_launcher(
        tmp_path,
        compositor="kwin",
        theme_json='{"current":"Tela-dark"}',
        inherited_theme="Tela-dark",
    )

    assert "QS_ICON_THEME" not in child
    assert "CAPARAZON_ICON_THEME" not in child
    assert child["QT_SCALE_FACTOR"] == "0.9"


def test_niri_launcher_uses_the_theme_reported_by_the_cli(tmp_path: Path) -> None:
    child = _run_launcher(
        tmp_path,
        compositor="niri",
        theme_json='{"current":"ThemeFromCli"}',
        inherited_theme="StaleTheme",
    )

    assert child["QS_ICON_THEME"] == "ThemeFromCli"
    assert child["CAPARAZON_ICON_THEME"] == "ThemeFromCli"


def test_launcher_is_posix_sh_compatible(tmp_path: Path) -> None:
    child = _run_launcher(
        tmp_path,
        compositor="niri",
        theme_json='{"current": "ThemeFromCli"}',
        inherited_theme="StaleTheme",
        runner="sh",
    )

    assert child["QS_ICON_THEME"] == "ThemeFromCli"
    assert child["CAPARAZON_ICON_THEME"] == "ThemeFromCli"

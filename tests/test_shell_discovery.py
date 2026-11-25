"""Tests del descubrimiento de la shell viva de Caparazón.

Desde que la shell arranca como servicio systemd, la fuente de verdad es la
unit ``caparazon-shell.service``. El``.desktop`` de autostart queda como
compatibilidad con instalaciones antiguas.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
HELPER = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-shell-path.sh"
IPC = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-shell-ipc.sh"
GUARDIAN = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-guardian.sh"
REPAIR = REPOSITORY_ROOT / "scripts" / "caparazon-repair"
INSTALLER = REPOSITORY_ROOT / "install.sh"


def _make_shell(root: Path) -> Path:
    """Crea una carpeta de shell mínima con su lanzador."""
    shell_dir = root / "Projects" / "caparazon-shell"
    (shell_dir / "scripts").mkdir(parents=True)
    _ = (shell_dir / "shell.qml").write_text("// shell\n", encoding="utf-8")
    launcher = shell_dir / "scripts" / "caparazon-shell"
    _ = launcher.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
    launcher.chmod(0o755)
    return shell_dir.resolve()


def _fake_systemctl(root: Path) -> Path:
    """Crea un ``systemctl`` que siempre falla, para aislar el sistema real."""
    fake_bin = root / "fakebin"
    fake_bin.mkdir(parents=True, exist_ok=True)
    fake = fake_bin / "systemctl"
    _ = fake.write_text("#!/bin/bash\nexit 1\n", encoding="utf-8")
    fake.chmod(0o755)
    return fake_bin


def _run_helper(config_home: Path, fake_bin: Path) -> subprocess.CompletedProcess[str]:
    """Ejecuta el helper con un ``XDG_CONFIG_HOME`` aislado."""
    env = dict(os.environ)
    env["XDG_CONFIG_HOME"] = str(config_home)
    env["HOME"] = str(config_home.parent)
    env["PATH"] = f"{fake_bin}{os.pathsep}{env.get('PATH', '')}"
    return subprocess.run(  # noqa: S603
        [str(HELPER)], env=env, capture_output=True, text=True, check=False
    )


def test_the_helper_is_executable() -> None:
    """El helper se invoca desde el IPC y el guardián, sin ``bash`` explícito."""
    assert os.access(HELPER, os.X_OK)


def test_the_helper_finds_the_shell_from_the_systemd_unit(tmp_path: Path) -> None:
    """La unit ``caparazon-shell.service`` es la fuente de verdad."""
    config_home = tmp_path / "config"
    shell_dir = _make_shell(tmp_path)
    unit_dir = config_home / "systemd" / "user"
    unit_dir.mkdir(parents=True)
    unit_text = f"[Service]\nExecStart={shell_dir}/scripts/caparazon-shell\n"
    _ = (unit_dir / "caparazon-shell.service").write_text(unit_text, encoding="utf-8")

    result = _run_helper(config_home, _fake_systemctl(tmp_path))

    assert result.returncode == 0
    assert result.stdout.strip() == str(shell_dir)


def test_the_helper_falls_back_to_the_legacy_autostart(tmp_path: Path) -> None:
    """Una instalación vieja, sin unit, sigue funcionando."""
    config_home = tmp_path / "config"
    shell_dir = _make_shell(tmp_path)
    autostart_dir = config_home / "autostart"
    autostart_dir.mkdir(parents=True)
    desktop_text = f"[Desktop Entry]\nExec={shell_dir}/scripts/caparazon-shell\n"
    _ = (autostart_dir / "caparazon.desktop").write_text(desktop_text, encoding="utf-8")

    result = _run_helper(config_home, _fake_systemctl(tmp_path))

    assert result.returncode == 0
    assert result.stdout.strip() == str(shell_dir)


def test_the_helper_fails_when_there_is_no_shell(tmp_path: Path) -> None:
    """Sin unit ni autostart, el helper lo dice y no inventa una ruta."""
    config_home = tmp_path / "config"
    config_home.mkdir(parents=True)

    result = _run_helper(config_home, _fake_systemctl(tmp_path))

    assert result.returncode == 1
    assert result.stdout.strip() == ""


def test_the_ipc_asks_the_helper_for_the_shell() -> None:
    """El IPC no puede quedarse sólo con el ``.desktop`` de autostart."""
    contents = IPC.read_text(encoding="utf-8")

    assert "caparazon-shell-path.sh" in contents


def test_the_guardian_watches_the_systemd_service() -> None:
    """El guardián reinicia la unit nueva, no la de autostart."""
    contents = GUARDIAN.read_text(encoding="utf-8")

    assert "caparazon-shell.service" in contents
    assert "caparazon-shell-path.sh" in contents
    assert "app-caparazon@autostart.service" not in contents


def test_the_repair_script_fixes_the_systemd_service() -> None:
    """``caparazon-repair`` repara la unit, no el ``.desktop``."""
    contents = REPAIR.read_text(encoding="utf-8")

    assert "caparazon-shell.service" in contents
    assert "caparazon-shell-path.sh" in contents
    assert "app-caparazon@autostart.service" not in contents


def test_the_installer_installs_the_helper() -> None:
    """El helper se instala junto al IPC para que lo encuentre."""
    contents = INSTALLER.read_text(encoding="utf-8")

    assert "caparazon-shell-path.sh" in contents
    assert '"$BIN_DIR/caparazon-shell-path"' in contents


def test_the_scale_dropin_targets_the_new_service() -> None:
    """El drop-in de escala debe seguir a la unit que arranca la shell."""
    contents = INSTALLER.read_text(encoding="utf-8")

    assert "caparazon-shell.service.d" in contents
    assert "app-caparazon@autostart.service.d" not in contents

"""Contrato y comportamiento del actualizador de la shell."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CHECK_SCRIPT = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-update-check.sh"
UPDATE_SCRIPT = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-update.sh"
QMLDIR = REPOSITORY_ROOT / "theme" / "qmldir"
UPDATE_STATUS = REPOSITORY_ROOT / "theme" / "UpdateStatus.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
CHIP = REPOSITORY_ROOT / "modules" / "bar" / "UpdateChip.qml"
PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "ShellConfigPanel.qml"
INSTALLER = REPOSITORY_ROOT / "install.sh"

GIT_ENV = os.environ | {
    "GIT_AUTHOR_NAME": "prueba",
    "GIT_AUTHOR_EMAIL": "prueba@example.com",
    "GIT_COMMITTER_NAME": "prueba",
    "GIT_COMMITTER_EMAIL": "prueba@example.com",
}


def run_git(cwd: Path, *args: str) -> None:
    subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        env=GIT_ENV,
    )


def build_clone(tmp_path: Path) -> tuple[Path, Path]:
    origin = tmp_path / "origin.git"
    subprocess.run(
        ["git", "init", "--bare", "--initial-branch=main", str(origin)],
        check=True,
        capture_output=True,
        env=GIT_ENV,
    )
    seed = tmp_path / "seed"
    run_git(tmp_path, "clone", str(origin), str(seed))
    (seed / "dato.txt").write_text("uno\n", encoding="utf-8")
    run_git(seed, "add", "dato.txt")
    run_git(seed, "commit", "-m", "inicial")
    run_git(seed, "push", "-u", "origin", "main")
    work = tmp_path / "work"
    run_git(tmp_path, "clone", str(origin), str(work))
    return seed, work


def push_new_commit(seed: Path) -> None:
    (seed / "dato.txt").write_text("dos\n", encoding="utf-8")
    run_git(seed, "commit", "-am", "segundo")
    run_git(seed, "push", "origin", "main")


def check(work: Path) -> str:
    result = subprocess.run(
        ["bash", str(CHECK_SCRIPT), str(work), "main"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def test_check_reports_uptodate(tmp_path: Path) -> None:
    _, work = build_clone(tmp_path)

    assert check(work) == "uptodate"


def test_check_reports_available_clean(tmp_path: Path) -> None:
    seed, work = build_clone(tmp_path)
    push_new_commit(seed)

    assert check(work) == "available 1 clean"


def test_check_reports_available_dirty(tmp_path: Path) -> None:
    seed, work = build_clone(tmp_path)
    push_new_commit(seed)
    (work / "dato.txt").write_text("local\n", encoding="utf-8")

    assert check(work) == "available 1 dirty"


def test_check_ignores_untracked_files(tmp_path: Path) -> None:
    _, work = build_clone(tmp_path)
    (work / "basura.log").write_text("x\n", encoding="utf-8")

    assert check(work) == "uptodate"


def test_check_reports_norepo(tmp_path: Path) -> None:
    plain = tmp_path / "sincopia"
    plain.mkdir()

    assert check(plain) == "norepo"


def test_check_reports_offline(tmp_path: Path) -> None:
    _, work = build_clone(tmp_path)
    run_git(work, "remote", "set-url", "origin", str(tmp_path / "no-existe"))

    assert check(work) == "offline"


def test_update_refuses_dirty_repo(tmp_path: Path) -> None:
    seed, work = build_clone(tmp_path)
    push_new_commit(seed)
    (work / "dato.txt").write_text("local\n", encoding="utf-8")
    cache = tmp_path / "cache"
    env = os.environ | {"XDG_CACHE_HOME": str(cache)}

    result = subprocess.run(
        ["bash", str(UPDATE_SCRIPT), str(work), str(work), "main"],
        capture_output=True,
        text=True,
        env=env,
    )

    assert result.returncode == 2
    assert (work / "dato.txt").read_text(encoding="utf-8") == "local\n"
    log = (cache / "caparazon" / "update.log").read_text(encoding="utf-8")
    assert "cambios locales" in log


def test_theme_registers_update_status() -> None:
    assert "singleton UpdateStatus 1.0 UpdateStatus.qml" in QMLDIR.read_text(
        encoding="utf-8"
    )


def test_update_status_checks_periodically_and_restarts_out_of_band() -> None:
    contents = UPDATE_STATUS.read_text(encoding="utf-8")

    assert "caparazon-update-check.sh" in contents
    assert "caparazon-update.sh" in contents
    assert "systemd-run" in contents
    assert "interval: 3600000" in contents


def test_pending_text_uses_the_singular_for_one_commit() -> None:
    contents = UPDATE_STATUS.read_text(encoding="utf-8")

    assert "pendingText" in contents
    assert '"1 commit nuevo en "' in contents


def test_bar_shows_the_chip_and_opens_configs() -> None:
    bar = BAR.read_text(encoding="utf-8")
    chip = CHIP.read_text(encoding="utf-8")

    assert "UpdateChip" in bar
    assert 'openSecondMenu("configs")' in bar
    assert "UpdateStatus.pending" in chip


def test_chip_sits_left_of_the_clock() -> None:
    contents = BAR.read_text(encoding="utf-8")
    center = contents.index("id: centerCluster")
    chip = contents.index("UpdateChip {", center)
    clock = contents.index("Clock {", center)

    assert center < chip < clock


def test_chip_animates_in_like_the_notification() -> None:
    chip = CHIP.read_text(encoding="utf-8")

    assert "width: shown ? (root.vertical ? Theme.barHeight : 26) : 0" in chip
    assert "visible: shown || width > 0.5" in chip
    assert "Behavior on width" in chip


def test_panel_offers_the_update_action() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "UpdateStatus.pending" in contents
    assert "UpdateStatus.startUpdate()" in contents


def test_panel_offers_a_manual_check() -> None:
    contents = PANEL.read_text(encoding="utf-8")

    assert "Buscar actualizaciones" in contents
    assert "UpdateStatus.refresh()" in contents
    assert "UpdateStatus.loaded" in contents


def test_installer_registers_the_updater() -> None:
    contents = INSTALLER.read_text(encoding="utf-8")

    assert "caparazon-update-check.sh" in contents
    assert "caparazon-update.sh" in contents
    assert "update.conf" in contents
    for key in ('"repo"', '"branch"', '"shell"'):
        assert key in contents

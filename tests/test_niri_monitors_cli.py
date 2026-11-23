from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLI = REPOSITORY_ROOT / "integration" / "bin" / "caparazon-wm.py"


def _load_cli() -> ModuleType:
    spec = importlib.util.spec_from_file_location("caparazon_wm", CLI)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def test_find_output_blocks_ignores_commented_examples() -> None:
    cli = _load_cli()
    text = '// output "DP-1" {\n//     mode "1024x768@60.004"\n// }\n'
    assert cli.find_output_blocks(text) == []


def test_read_output_configs_parses_all_fields() -> None:
    cli = _load_cli()
    path = Path(tempfile.mkdtemp()) / "15-outputs.kdl"
    path.write_text(
        'output "HDMI-A-1" {\n'
        '    mode "1920x1080@60.000"\n'
        '    scale 1.5\n'
        '    transform "90"\n'
        '    position x=1024 y=0\n'
        '    focus-at-startup\n'
        '    variable-refresh-rate\n'
        '}\n',
        encoding="utf-8",
    )
    assert cli.read_output_configs(path) == {
        "HDMI-A-1": cli.OutputBlock(
            name="HDMI-A-1",
            mode="1920x1080@60.000",
            scale=1.5,
            transform="90",
            x=1024,
            y=0,
            primary=True,
            vrr=True,
        )
    }


def test_render_output_configs_emits_primary_and_vrr() -> None:
    cli = _load_cli()
    block = cli.OutputBlock(
        name="DP-1",
        mode="1024x768@60.004",
        scale=1,
        transform="normal",
        x=0,
        y=0,
        primary=True,
        vrr=False,
    )
    text = cli.render_output_configs({"DP-1": block})
    assert 'output "DP-1" {' in text
    assert 'mode "1024x768@60.004"' in text
    assert "scale 1" in text
    assert 'transform "normal"' in text
    assert "position x=0 y=0" in text
    assert "focus-at-startup" in text
    assert "variable-refresh-rate" not in text


def test_write_output_configs_adds_include_once() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    root.parent.mkdir(parents=True, exist_ok=True)
    root.write_text('include "config.d/10-input-and-cursor.kdl"\n', encoding="utf-8")
    block = cli.OutputBlock(
        name="HDMI-A-1",
        mode="1920x1080@60.000",
        scale=1,
        transform="normal",
        x=1024,
        y=0,
        primary=True,
        vrr=False,
    )
    target = cli.write_output_configs(root, {"HDMI-A-1": block})
    cli.write_output_configs(root, {"HDMI-A-1": block})
    assert target == root.parent / "config.d" / "15-outputs.kdl"
    config_text = root.read_text(encoding="utf-8")
    assert config_text.count('include "config.d/15-outputs.kdl"') == 1


def test_foreign_output_files_ignores_comments_and_own_file() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    config_d = root.parent / "config.d"
    config_d.mkdir(parents=True)
    root.write_text(
        'include "config.d/10-input-and-cursor.kdl"\n'
        'include "config.d/15-outputs.kdl"\n'
        'include "config.d/90-user-extra.kdl"\n',
        encoding="utf-8",
    )
    (config_d / "10-input-and-cursor.kdl").write_text(
        '// output "eDP-1" {\n//     mode "1920x1080@60.000"\n// }\n',
        encoding="utf-8",
    )
    own = config_d / "15-outputs.kdl"
    own.write_text('output "DP-1" {\n    mode "1024x768@60.004"\n}\n', encoding="utf-8")
    (config_d / "90-user-extra.kdl").write_text(
        'output "HDMI-A-1" {\n    mode "1920x1080@60.000"\n}\n',
        encoding="utf-8",
    )
    files = cli.foreign_output_files(root)
    assert files == [config_d / "90-user-extra.kdl"]


def test_configured_primary_output_uses_focus_at_startup() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    cli.write_output_configs(
        root,
        {
            "HDMI-A-1": cli.OutputBlock(
                name="HDMI-A-1",
                mode="1920x1080@60.000",
                scale=1,
                transform="normal",
                x=1024,
                y=0,
                primary=True,
                vrr=False,
            )
        },
    )
    previous_niri_config = os.environ.get("NIRI_CONFIG")
    os.environ["NIRI_CONFIG"] = str(root)
    try:
        outs = {"HDMI-A-1": {"current_mode": 0}, "DP-1": {"current_mode": 0}}
        assert cli.configured_primary_output(outs) == "HDMI-A-1"
    finally:
        if previous_niri_config is None:
            os.environ.pop("NIRI_CONFIG", None)
        else:
            os.environ["NIRI_CONFIG"] = previous_niri_config


def _run_cli(
    args: list[str],
    *,
    env_extra: dict[str, str] | None = None,
    fake_bin: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.pop("NIRI_SOCKET", None)
    if env_extra:
        env.update(env_extra)
    if fake_bin:
        tmp = tempfile.mkdtemp(prefix="cwm-mon-")
        for name, body in fake_bin.items():
            _write_exec(Path(tmp) / name, body)
        env["PATH"] = tmp + os.pathsep + env.get("PATH", "")
    return subprocess.run(  # noqa: S603
        ["python3", str(CLI), *args],  # noqa: S607
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )


FAKE_NIRI_OUTPUTS = """#!/bin/sh
case "$*" in
  *version*) echo "26.04"; exit 0 ;;
  *outputs*)
    cat <<'JSON'
{
  "HDMI-A-1": {
    "name": "HDMI-A-1", "make": "Xiaomi Corporation", "model": "P27FBA-RAGL",
    "serial": "5106500094111", "current_mode": 0, "vrr_enabled": false,
    "logical": {
      "x": 1024, "y": 0, "width": 1920, "height": 1080,
      "scale": 1.0, "transform": "Normal"
    },
    "modes": [
      {"width": 1920, "height": 1080, "refresh_rate": 60000, "is_preferred": true},
      {"width": 1280, "height": 720, "refresh_rate": 75000, "is_preferred": false}
    ]
  },
  "DP-1": {
    "name": "DP-1", "make": "Integrated Tech Express Inc", "model": "DP2VGA V235",
    "serial": "", "current_mode": 0, "vrr_enabled": false,
    "logical": {
      "x": 0, "y": 0, "width": 1024, "height": 768,
      "scale": 1.0, "transform": "Normal"
    },
    "modes": [
      {"width": 1024, "height": 768, "refresh_rate": 60004, "is_preferred": true}
    ]
  }
}
JSON
    exit 0 ;;
  *) exit 1 ;;
esac
"""


def test_mode_label_formats_millihertz() -> None:
    cli = _load_cli()
    assert cli.mode_label(1920, 1080, 60000) == "1920x1080@60.000"
    assert cli.mode_label(1024, 768, 60004) == "1024x768@60.004"
    assert cli.mode_label(1280, 720, 59940) == "1280x720@59.940"


def test_monitor_state_reports_configured_primary_and_logical_position() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    cli.write_output_configs(
        root,
        {
            "HDMI-A-1": cli.OutputBlock(
                name="HDMI-A-1",
                mode="1920x1080@60.000",
                scale=1,
                transform="normal",
                x=1024,
                y=0,
                primary=True,
                vrr=False,
            )
        },
    )
    result = _run_cli(
        ["monitors"],
        env_extra={
            "NIRI_SOCKET": "/run/user/1000/niri.sock",
            "NIRI_CONFIG": str(root),
        },
        fake_bin={"niri": FAKE_NIRI_OUTPUTS},
    )
    assert result.returncode == 0, result.stderr
    state = json.loads(result.stdout)
    hdmi = next(item for item in state["outputs"] if item["name"] == "HDMI-A-1")
    assert hdmi["primary"] is True
    assert hdmi["primary_configured"] is True
    assert hdmi["transform"] == "normal"
    assert hdmi["x"] == 1024
    assert hdmi["y"] == 0
    assert hdmi["mode"] == "1920x1080@60.000"
    assert hdmi["modes"][0] == {
        "label": "1920x1080@60.000",
        "preferred": True,
        "current": True,
    }
    assert state["configured"] is True
    assert state["error"] == ""


def test_monitor_state_reports_non_niri_compositor() -> None:
    result = _run_cli(
        ["monitors"],
        fake_bin={
            "busctl": '#!/bin/sh\necho \'s "DP-1"\'\n',
            "niri": "#!/bin/sh\nexit 1\n",
        },
    )
    assert result.returncode == 0, result.stderr
    state = json.loads(result.stdout)
    assert state["outputs"] == []
    assert "sólo niri" in state["error"]


FAKE_NIRI_APPLY = """#!/bin/sh
case "$*" in
  *version*) echo "26.04"; exit 0 ;;
  *outputs*)
    cat <<'JSON'
{
  "HDMI-A-1": {
    "name": "HDMI-A-1", "current_mode": 0, "vrr_enabled": false,
    "logical": {
      "x": 1024, "y": 0, "width": 1920, "height": 1080,
      "scale": 1.0, "transform": "Normal"
    },
    "modes": [
      {"width": 1920, "height": 1080, "refresh_rate": 60000, "is_preferred": true}
    ]
  }
}
JSON
    exit 0 ;;
  *load-config-file*) echo "reload" >> "$NIRI_LOG"; exit 0 ;;
  *focus-monitor*) echo "focus:$4" >> "$NIRI_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
"""


def _apply_env(root: Path, log: Path) -> dict[str, str]:
    return {
        "NIRI_SOCKET": "/run/user/1000/niri.sock",
        "NIRI_CONFIG": str(root),
        "NIRI_LOG": str(log),
    }


def test_apply_writes_blocks_includes_reloads_and_focuses() -> None:
    cli = _load_cli()
    tmp = Path(tempfile.mkdtemp())
    root = tmp / "config.kdl"
    root.write_text('include "config.d/10-input-and-cursor.kdl"\n', encoding="utf-8")
    log = tmp / "niri.log"
    payload = {
        "primary": "HDMI-A-1",
        "outputs": [
            {
                "name": "HDMI-A-1",
                "mode": "1920x1080@60.000",
                "transform": "normal",
                "x": 1024,
                "y": 0,
            }
        ],
    }
    result = _run_cli(
        ["monitors", "--apply", json.dumps(payload)],
        env_extra=_apply_env(root, log),
        fake_bin={"niri": FAKE_NIRI_APPLY},
    )
    assert result.returncode == 0, result.stderr
    text = cli.output_config_path(root).read_text(encoding="utf-8")
    assert 'output "HDMI-A-1" {' in text
    assert "focus-at-startup" in text
    config_text = root.read_text(encoding="utf-8")
    assert config_text.count('include "config.d/15-outputs.kdl"') == 1
    assert log.read_text(encoding="utf-8").splitlines() == ["reload", "focus:HDMI-A-1"]


def test_apply_rejects_unavailable_mode_without_writing() -> None:
    cli = _load_cli()
    tmp = Path(tempfile.mkdtemp())
    root = tmp / "config.kdl"
    root.write_text('include "config.d/10-input-and-cursor.kdl"\n', encoding="utf-8")
    payload = {
        "primary": "HDMI-A-1",
        "outputs": [
            {
                "name": "HDMI-A-1",
                "mode": "3840x2160@60.000",
                "transform": "normal",
                "x": 0,
                "y": 0,
            }
        ],
    }
    result = _run_cli(
        ["monitors", "--apply", json.dumps(payload)],
        env_extra=_apply_env(root, tmp / "niri.log"),
        fake_bin={"niri": FAKE_NIRI_APPLY},
    )
    assert result.returncode == 1
    assert "modo no disponible" in result.stderr
    assert not cli.output_config_path(root).exists()


def test_apply_refuses_foreign_output_blocks() -> None:
    tmp = Path(tempfile.mkdtemp())
    root = tmp / "config.kdl"
    config_d = tmp / "config.d"
    config_d.mkdir()
    root.write_text('include "config.d/90-user-extra.kdl"\n', encoding="utf-8")
    (config_d / "90-user-extra.kdl").write_text(
        'output "HDMI-A-1" {\n    mode "1920x1080@60.000"\n}\n', encoding="utf-8"
    )
    payload = {
        "primary": "HDMI-A-1",
        "outputs": [
            {
                "name": "HDMI-A-1",
                "mode": "1920x1080@60.000",
                "transform": "normal",
                "x": 0,
                "y": 0,
            }
        ],
    }
    result = _run_cli(
        ["monitors", "--apply", json.dumps(payload)],
        env_extra=_apply_env(root, tmp / "niri.log"),
        fake_bin={"niri": FAKE_NIRI_APPLY},
    )
    assert result.returncode == 1
    assert "fuera de config.d/15-outputs.kdl" in result.stderr


def test_apply_preserves_disconnected_output_blocks() -> None:
    cli = _load_cli()
    tmp = Path(tempfile.mkdtemp())
    root = tmp / "config.kdl"
    block = cli.OutputBlock(
        name="DP-2", mode="2560x1440@120.000", scale=1,
        transform="normal", x=-2560, y=0, primary=False, vrr=False,
    )
    cli.write_output_configs(root, {"DP-2": block})
    payload = {
        "primary": "HDMI-A-1",
        "outputs": [
            {
                "name": "HDMI-A-1",
                "mode": "1920x1080@60.000",
                "transform": "normal",
                "x": 1024,
                "y": 0,
            }
        ],
    }
    result = _run_cli(
        ["monitors", "--apply", json.dumps(payload)],
        env_extra=_apply_env(root, tmp / "niri.log"),
        fake_bin={"niri": FAKE_NIRI_APPLY},
    )
    assert result.returncode == 0, result.stderr
    text = cli.output_config_path(root).read_text(encoding="utf-8")
    assert 'output "DP-2" {' in text
    assert "position x=-2560 y=0" in text


def test_primary_output_uses_configured_monitor_over_top_left() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    cli.write_output_configs(
        root,
        {
            "HDMI-A-1": cli.OutputBlock(
                name="HDMI-A-1", mode="1920x1080@60.000", scale=1,
                transform="normal", x=1024, y=0, primary=True, vrr=False,
            )
        },
    )
    result = _run_cli(
        ["primary-output"],
        env_extra={"NIRI_SOCKET": "/run/user/1000/niri.sock", "NIRI_CONFIG": str(root)},
        fake_bin={"niri": FAKE_NIRI_OUTPUTS},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "HDMI-A-1"


def test_primary_output_ignores_configured_but_disconnected_monitor() -> None:
    cli = _load_cli()
    root = Path(tempfile.mkdtemp()) / "config.kdl"
    cli.write_output_configs(
        root,
        {
            "eDP-1": cli.OutputBlock(
                name="eDP-1", mode="1920x1080@60.000", scale=1,
                transform="normal", x=0, y=0, primary=True, vrr=False,
            )
        },
    )
    result = _run_cli(
        ["primary-output"],
        env_extra={"NIRI_SOCKET": "/run/user/1000/niri.sock", "NIRI_CONFIG": str(root)},
        fake_bin={"niri": FAKE_NIRI_OUTPUTS},
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "DP-1"

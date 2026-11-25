"""Contrato del subcomando app-theme de caparazon-wm."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Protocol, TypedDict, cast

from tests.test_caparazon_wm import CLI, REPOSITORY_ROOT

if TYPE_CHECKING:
    from subprocess import CompletedProcess
    from types import ModuleType

APP_THEME_CLI = CLI


class _AppThemeCliModule(Protocol):
    APP_THEME_OWN_OUTPUTS: dict[str, str]
    APP_THEME_APP_OUTPUTS: dict[str, str]
    APP_THEME_TOKENS: tuple[tuple[str, str], ...]


class _TokenPayload(TypedDict):
    name: str
    hex: str


class _StatePayload(TypedDict):
    style: str
    selected: str
    engineAvailable: bool
    tokens: list[_TokenPayload]
    error: str


class _SetPayload(TypedDict):
    style: str
    token: str
    hex: str
    outputs: list[str]
    apps: list[object]
    live: list[object]


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _load_cli_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("caparazon_wm", CLI)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _app_theme_module() -> _AppThemeCliModule:
    return cast("_AppThemeCliModule", cast("object", _load_cli_module()))


def _run_cli(
    args: list[str],
    *,
    env_extra: dict[str, str] | None = None,
    fake_bin: dict[str, str] | None = None,
) -> CompletedProcess[str]:
    env = os.environ.copy()
    env.pop("NIRI_SOCKET", None)
    if env_extra:
        env.update(env_extra)
    path_prepend = ""
    if fake_bin:
        tmp = tempfile.mkdtemp(prefix="cwm-")
        binpath = Path(tmp)
        for name, body in fake_bin.items():
            _write_exec(binpath / name, body)
        path_prepend = str(binpath) + os.pathsep
    env["PATH"] = path_prepend + env.get("PATH", "")
    return subprocess.run(  # noqa: S603
        ["python3", str(CLI), *args],  # noqa: S607
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=False,
    )


def _json_object(text: str) -> dict[str, object]:
    return cast("dict[str, object]", json.loads(text))


def _state_payload(text: str) -> _StatePayload:
    return cast("_StatePayload", cast("object", _json_object(text)))


def _set_payload(text: str) -> _SetPayload:
    return cast("_SetPayload", cast("object", _json_object(text)))


_STYLE_PALETTE_FILES = {
    "material": "colors.json",
    "oled": "colors-oled.json",
    "perla": "colors-perla.json",
}

_BASE_PALETTE = {
    "surface": "#101010",
    "surfaceContainerLowest": "#080808",
    "surfaceContainerLow": "#0c0c0c",
    "surfaceContainer": "#121212",
    "surfaceContainerHigh": "#181818",
    "surfaceContainerHighest": "#1e1e1e",
    "fgSurface": "#f2f2f2",
    "fgSurfaceVariant": "#b8b8b8",
    "outline": "#6e6e6e",
    "outlineVariant": "#2a2a2a",
    "primary": "#ff908d",
    "fgPrimary": "#680012",
    "secondary": "#ff908d",
    "tertiary": "#4ccfdf",
    "error": "#ff9285",
    "errorContainer": "#930009",
    "fgErrorContainer": "#ffc9c3",
}


def _run_app_theme_cli(
    args: list[str],
    *,
    env_extra: dict[str, str] | None = None,
    fake_bin: dict[str, str] | None = None,
) -> CompletedProcess[str]:
    return _run_cli(args, env_extra=env_extra, fake_bin=fake_bin)


def _write_style(path: Path, style: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps({"style": style, "auto": False}) + "\n", encoding="utf-8"
    )


def _write_app_theme_palette(home: Path, style: str, **overrides: str) -> Path:
    palette = dict(_BASE_PALETTE)
    palette.update(overrides)
    path = home / ".cache" / "caparazon" / _STYLE_PALETTE_FILES[style]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(palette, indent=2) + "\n", encoding="utf-8")
    return path


def _app_theme_env(
    tmp_path: Path, *, style: str = "oled"
) -> tuple[dict[str, str], Path]:
    home = tmp_path / "home"
    config = home / ".config"
    cache = home / ".cache"
    data = home / ".local" / "share"
    for path in (config, cache, data):
        path.mkdir(parents=True, exist_ok=True)
    _write_style(config / "caparazon" / "style.json", style)
    for name in _STYLE_PALETTE_FILES:
        _write_app_theme_palette(home, name)
    environ = {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(config),
        "XDG_CACHE_HOME": str(cache),
        "XDG_DATA_HOME": str(data),
        "NIRI_SOCKET": "/run/user/1000/niri.sock",
    }
    return environ, home


def _tree_snapshot(root: Path) -> dict[str, str]:
    if root.is_file():
        return {str(root): hashlib.sha256(root.read_bytes()).hexdigest()}
    if not root.exists():
        return {}
    return {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def _tree_snapshot_many(
    roots: Path | list[Path] | tuple[Path, ...],
) -> dict[str, str]:
    if not isinstance(roots, (list, tuple)):
        return _tree_snapshot(roots)
    snapshot: dict[str, str] = {}
    for root in roots:
        snapshot.update(_tree_snapshot(root))
    return snapshot


def test_app_theme_state_lists_17_tokens_for_active_style(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path, style="oled")
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    payload = _state_payload(result.stdout)
    assert payload["style"] == "oled"
    assert [item["name"] for item in payload["tokens"]] == [
        "surface", "surfaceContainerLowest", "surfaceContainerLow",
        "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest",
        "fgSurface", "fgSurfaceVariant", "outline", "outlineVariant",
        "primary", "fgPrimary", "secondary", "tertiary", "error",
        "errorContainer", "fgErrorContainer",
    ]
    tertiary = next(item for item in payload["tokens"] if item["name"] == "tertiary")
    assert tertiary["hex"] == "#4ccfdf"


def test_app_theme_state_follows_style_json(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path, style="oled")
    _write_style(home / ".config" / "caparazon" / "style.json", "perla")
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    payload = _state_payload(result.stdout)
    assert payload["style"] == "perla"


def test_app_theme_state_uses_material_when_style_missing(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path, style="oled")
    (home / ".config" / "caparazon" / "style.json").unlink()
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    payload = _state_payload(result.stdout)
    assert payload["style"] == "material"


def test_app_theme_state_reports_invalid_palette(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    _write_app_theme_palette(home, "oled", primary="rojo")
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    payload = _state_payload(result.stdout)
    assert payload["error"]
    assert len(payload["tokens"]) == 17
    assert all(item["hex"] == "" for item in payload["tokens"])


def test_app_theme_state_reads_selection(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    (home / ".config" / "caparazon" / "app-theme.json").write_text(
        '{"token":"tertiary"}\n', encoding="utf-8"
    )
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    payload = _state_payload(result.stdout)
    assert payload["selected"] == "tertiary"


def test_app_theme_cli_prints_state_json(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    assert set(_state_payload(result.stdout)) == {
        "style", "selected", "engineAvailable", "tokens", "error"
    }


def test_app_theme_cli_rejects_unknown_option(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme", "--bogus"], env_extra=environ)
    assert result.returncode == 2
    assert "app-theme [--set" in result.stderr


_FAKE_ENGINE_FILES = {
    "__init__.py": "",
    "accent.py": """\
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Accent:
    red: int
    green: int
    blue: int


def accent_to_hex(accent: Accent) -> str:
    return f"#{accent.red:02x}{accent.green:02x}{accent.blue:02x}"
""",
    "matugen.py": """\
from __future__ import annotations

import json
import os
import re
from pathlib import Path


def find_matugen(environ):
    raw = environ.get("MATUGEN")
    if not raw:
        return None
    candidate = Path(raw)
    return candidate if candidate.is_file() else None


class FakeTokens:
    def __init__(self, accent):
        self.accent = accent

    def app_environment(self):
        return {"MATUGEN_ACCENT": self.accent}


def invoke_matugen(binary, accent, config, *, timeout=60.0):
    log = os.environ.get("APP_THEME_TEST_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as handle:
            handle.write(json.dumps({"accent": accent, "config": str(config)}) + "\\n")
    text = config.read_text(encoding="utf-8")
    outputs = re.findall(r'^output_path = (".*")$', text, re.MULTILINE)
    for raw in outputs:
        staging = Path(json.loads(raw))
        staging.parent.mkdir(parents=True, exist_ok=True)
        staging.write_text(f"seed={accent}\\n", encoding="utf-8")
    return FakeTokens(accent)
""",
    "registry.py": """\
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class Descriptor:
    name: str
    input_path: str
    output_path: str
    saturation: float | None = None


@dataclass(frozen=True, slots=True)
class TemplateRegistration:
    name: str
    input_path: Path
    output_path: Path
    saturation: float | None = None

    @property
    def staging_path(self):
        return self.output_path.with_name(
            f"{self.output_path.stem}.staging{self.output_path.suffix}"
        )


def parse_descriptor(path):
    values = {}
    saturation = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        key, raw_value = line.split("=", 1)
        key = key.strip()
        value = json.loads(raw_value.strip())
        if key == "saturation":
            saturation = float(value)
        else:
            values[key] = value
    return Descriptor(
        name=values["name"],
        input_path=values["input_path"],
        output_path=values["output_path"],
        saturation=saturation,
    )


def expand_home_path(raw_path, home):
    if raw_path == "~":
        path = home
    elif raw_path.startswith("~/"):
        path = home / raw_path.removeprefix("~/")
    else:
        path = Path(raw_path)
    if not path.is_absolute():
        path = home / path
    return path.resolve(strict=False)


def _toml_string(value):
    return json.dumps(value, ensure_ascii=False)


def render_matugen_config(registrations):
    lines = ["[config]", "version_check = false", "caching = false"]
    for registration in sorted(registrations, key=lambda item: item.name):
        lines.extend((
            "",
            f"[templates.{registration.name}]",
            f"input_path = {_toml_string(str(registration.input_path))}",
            f"output_path = {_toml_string(str(registration.staging_path))}",
        ))
    return "\\n".join(lines) + "\\n"
""",
    "apps/__init__.py": """\
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path


def _append(entry):
    log = os.environ.get("APP_THEME_TEST_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry) + "\\n")


@dataclass(frozen=True, slots=True)
class AppPaths:
    home: Path

    @classmethod
    def from_environment(cls, environ):
        return cls(Path(environ.get("HOME", str(Path.home()))))


@dataclass(frozen=True, slots=True)
class AppResult:
    app: str
    status: str
    detail: str = ""


def apply_app_integrations(paths, accent, palette):
    _append({
        "kind": "apps",
        "rgb": [accent.red, accent.green, accent.blue],
        "MATUGEN_ACCENT": palette["MATUGEN_ACCENT"],
    })
    return (
        AppResult("brave", "applied"),
        AppResult("equibop", "applied"),
        AppResult("materialgram", "applied"),
        AppResult("obs", "applied"),
    )
""",
    "live/__init__.py": """\
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path


def _append(entry):
    log = os.environ.get("APP_THEME_TEST_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry) + "\\n")


@dataclass(frozen=True, slots=True)
class LivePaths:
    home: Path

    @classmethod
    def from_environment(cls, environ):
        return cls(Path(environ.get("HOME", str(Path.home()))))


@dataclass(frozen=True, slots=True)
class LiveResult:
    app: str
    status: str
    detail: str = ""


def apply_live_integrations(paths, accent, environ):
    _append({"kind": "live", "accent": accent})
    return (
        LiveResult("kitty", "applied"),
        LiveResult("ghostty", "applied"),
        LiveResult("zen", "applied"),
        LiveResult("cava", "applied"),
        LiveResult("millennium", "applied"),
    )
""",
}


def _write_fake_engine(root: Path) -> dict[str, str]:
    source_root = root / ".local" / "share" / "accent-theme" / "source"
    package = source_root / "src" / "accent_theme"
    (package / "apps").mkdir(parents=True, exist_ok=True)
    (package / "live").mkdir(parents=True, exist_ok=True)
    for relative, body in _FAKE_ENGINE_FILES.items():
        (package / relative).write_text(body, encoding="utf-8")
    fake_binary = root.parent / "fake-matugen"
    _write_exec(fake_binary, "#!/bin/sh\nexit 0\n")
    return {
        "ACCENT_THEME_SOURCE": str(source_root),
        "MATUGEN": str(fake_binary),
    }


def _write_descriptor(
    path: Path, name: str, input_path: Path, output_path: Path
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"name = {json.dumps(name)}",
        f"input_path = {json.dumps(str(input_path))}",
        f"output_path = {json.dumps(str(output_path))}",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_app_theme_assets(home: Path) -> None:
    cli = _app_theme_module()
    own_templates = home / ".config" / "caparazon" / "app-theme" / "templates"
    own_descriptors = home / ".config" / "caparazon" / "app-theme" / "templates.d"
    external_templates = home / ".config" / "accent-theme" / "templates"
    external_descriptors = home / ".config" / "accent-theme" / "templates.d"
    for name, relative_output in cli.APP_THEME_OWN_OUTPUTS.items():
        template = own_templates / f"{name}.tmpl"
        template.parent.mkdir(parents=True, exist_ok=True)
        template.write_text(f"own {name}\n", encoding="utf-8")
        _write_descriptor(
            own_descriptors / f"{name}.toml",
            name,
            template,
            home / relative_output,
        )
    for name, relative_output in cli.APP_THEME_APP_OUTPUTS.items():
        template = external_templates / f"{name}.tmpl"
        template.parent.mkdir(parents=True, exist_ok=True)
        template.write_text(f"external {name}\n", encoding="utf-8")
        _write_descriptor(
            external_descriptors / f"{name}.toml",
            name,
            template,
            home / relative_output,
        )


def test_app_theme_token_order_matches_required_tokens_file() -> None:
    required = REPOSITORY_ROOT / "integration" / "theme" / "required-tokens.txt"
    lines = required.read_text(encoding="utf-8").splitlines()
    expected = [line.strip() for line in lines if line.strip()]
    cli = _app_theme_module()
    assert [name for name, _ in cli.APP_THEME_TOKENS] == expected


def test_fake_app_theme_engine_is_available(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    assert _state_payload(result.stdout)["engineAvailable"] is True


def test_app_theme_engine_unavailable_without_source(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme"], env_extra=environ)
    assert _state_payload(result.stdout)["engineAvailable"] is False


def test_app_theme_config_uses_own_templates(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    config = (
        home / ".cache" / "caparazon" / "app-theme" / "matugen.toml"
    ).read_text(encoding="utf-8")
    assert "[templates.caparazon-app-gtk3]" in config
    assert str(home / ".config" / "gtk-3.0" / "colors.staging.css") in config
    assert "[templates.cava-matugen]" in config


def test_app_theme_config_excludes_shell_templates(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    config = (
        home / ".cache" / "caparazon" / "app-theme" / "matugen.toml"
    ).read_text(encoding="utf-8")
    assert "caparazon-shell" not in config
    assert "colors.staging.json" not in config


def test_app_theme_config_ignores_unknown_app_descriptors(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    rogue = home / ".config" / "accent-theme" / "templates.d" / "rogue.toml"
    rogue.write_text(
        "\n".join(
            [
                'name = "rogue-matugen"',
                f'input_path = "{home}/x"',
                f'output_path = "{home}/.config/kdeglobals"',
                "",
            ]
        ),
        encoding="utf-8",
    )
    _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    config = (
        home / ".cache" / "caparazon" / "app-theme" / "matugen.toml"
    ).read_text(encoding="utf-8")
    assert "rogue-matugen" not in config
    assert "kdeglobals" not in config


FAKE_BUSCTL_KWIN_OK = """#!/bin/sh
echo 's "DP-1"'
exit 0
"""


def _assert_tree_unchanged(root: Path, before: dict[str, str]) -> None:
    assert _tree_snapshot(root) == before


def test_app_theme_config_never_touches_accent_theme_config(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    foreign = home / ".config" / "accent-theme" / "matugen.toml"
    foreign.write_text("config original\n", encoding="utf-8")
    before = _tree_snapshot(foreign)
    _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert _tree_snapshot(foreign) == before


def test_app_theme_set_refuses_in_kwin_without_writes(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.pop("NIRI_SOCKET", None)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    before = _tree_snapshot(home)
    result = _run_app_theme_cli(
        ["app-theme", "--set", "primary"],
        env_extra=environ,
        fake_bin={"busctl": FAKE_BUSCTL_KWIN_OK},
    )
    assert result.returncode == 1
    assert "sólo niri" in result.stderr
    _assert_tree_unchanged(home, before)


def test_app_theme_set_rejects_unknown_token_without_writes(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    before = _tree_snapshot(home)
    result = _run_app_theme_cli(["app-theme", "--set", "cactus"], env_extra=environ)
    assert result.returncode == 1
    assert "token inválido" in result.stderr
    _assert_tree_unchanged(home, before)


def test_app_theme_set_rejects_invalid_hex_without_writes(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    _write_app_theme_palette(home, "oled", primary="#zzzzzz")
    before = _tree_snapshot(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 1
    assert "paleta" in result.stderr
    _assert_tree_unchanged(home, before)


def test_app_theme_set_refuses_when_engine_missing_without_writes(
    tmp_path: Path,
) -> None:
    environ, home = _app_theme_env(tmp_path)
    _write_app_theme_assets(home)
    before = _tree_snapshot(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 1
    assert result.stderr == "app-theme: motor accent-theme no disponible\n"
    _assert_tree_unchanged(home, before)


def test_app_theme_help_reports_usage(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme", "--help"], env_extra=environ)
    assert result.returncode == 2
    assert "app-theme [--set <token>]" in result.stderr


def test_app_theme_set_without_value_reports_usage(tmp_path: Path) -> None:
    environ, _ = _app_theme_env(tmp_path)
    result = _run_app_theme_cli(["app-theme", "--set"], env_extra=environ)
    assert result.returncode == 2
    assert "app-theme --set <token>" in result.stderr


def _read_log(path: Path) -> list[dict[str, object]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    return [_json_object(line) for line in lines if line]


def test_app_theme_set_invokes_matugen_with_selected_seed(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    log = tmp_path / "matugen.log"
    environ["APP_THEME_TEST_LOG"] = str(log)
    result = _run_app_theme_cli(["app-theme", "--set", "tertiary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    entry = _read_log(log)[0]
    assert entry["accent"] == "#4ccfdf"
    expected = home / ".cache" / "caparazon" / "app-theme" / "matugen.toml"
    assert entry["config"] == str(expected)


def test_app_theme_set_uses_own_matugen_config(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    generated = (
        home / ".cache" / "caparazon" / "app-theme" / "matugen.toml"
    ).read_text(encoding="utf-8")
    assert generated.startswith("[config]\n")
    assert str(home / ".config" / "accent-theme" / "matugen.toml") not in generated


def test_app_theme_set_publishes_only_allowed_outputs(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    payload = _set_payload(result.stdout)
    outputs = set(payload["outputs"])
    assert str(home / ".config" / "gtk-3.0" / "colors.css") in outputs
    assert str(home / ".config" / "kitty" / "theme.conf") in outputs
    assert str(home / ".config" / "kdeglobals") not in outputs
    assert (home / ".config" / "gtk-3.0" / "colors.css").is_file()


def test_app_theme_set_cleans_staging_files(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    staging = [path for path in home.rglob("*.staging*") if path.is_file()]
    assert staging == []


def test_app_theme_set_calls_app_integrations_with_explicit_accent(
    tmp_path: Path,
) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    log = tmp_path / "integrations.log"
    environ["APP_THEME_TEST_LOG"] = str(log)
    result = _run_app_theme_cli(["app-theme", "--set", "tertiary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    entries = _read_log(log)
    app_entry = next(item for item in entries if item.get("kind") == "apps")
    assert app_entry["rgb"] == [76, 207, 223]
    assert app_entry["MATUGEN_ACCENT"] == "#4ccfdf"


def test_app_theme_set_calls_live_integrations_with_explicit_accent(
    tmp_path: Path,
) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    log = tmp_path / "integrations.log"
    environ["APP_THEME_TEST_LOG"] = str(log)
    result = _run_app_theme_cli(["app-theme", "--set", "tertiary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    entries = _read_log(log)
    live_entry = next(item for item in entries if item.get("kind") == "live")
    assert live_entry["accent"] == "#4ccfdf"


def test_app_theme_set_writes_selection_and_result_json(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    selected = "primary"
    result = _run_app_theme_cli(["app-theme", "--set", selected], env_extra=environ)
    payload = _set_payload(result.stdout)
    assert set(payload) == {"style", "token", "hex", "outputs", "apps", "live"}
    assert payload["token"] == selected
    assert payload["hex"] == "#ff908d"
    selection = (home / ".config" / "caparazon" / "app-theme.json").read_text(
        encoding="utf-8"
    )
    assert _json_object(selection) == {"token": selected}
    assert list((home / ".config" / "caparazon").glob("app-theme.json.*")) == []


def test_app_theme_set_preserves_shell_and_kde_files(tmp_path: Path) -> None:
    environ, home = _app_theme_env(tmp_path)
    environ.update(_write_fake_engine(home))
    _write_app_theme_assets(home)
    protected = [
        home / ".config" / "caparazon" / "style.json",
        home / ".cache" / "caparazon" / "colors.json",
        home / ".cache" / "caparazon" / "colors-oled.json",
        home / ".cache" / "caparazon" / "colors-perla.json",
        home / ".config" / "kdeglobals",
        home / ".config" / "accent-theme" / "matugen.toml",
    ]
    before = _tree_snapshot_many(protected)
    result = _run_app_theme_cli(["app-theme", "--set", "primary"], env_extra=environ)
    assert result.returncode == 0, result.stderr
    assert _tree_snapshot_many(protected) == before

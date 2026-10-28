#!/usr/bin/env python3
"""
Alimentador único: lee el AccentColor de KDE y se lo pasa a matugen.
Matugen genera fondos/acentos de config.toml; la paleta familia ANSI
(mismo matiz, distinta luz/saturación) la calcula este script porque
las plantillas no pueden hacer matemática de color.
"""
import colorsys
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_theme import get_accent_rgb, hsv_to_hex

CACHE_DIR = os.path.expanduser("~/.cache/caparazon")


def _find_matugen():
    """Ruta a matugen: $MATUGEN, PATH o instalación local. None si falta."""
    for cand in (os.environ.get("MATUGEN"), shutil.which("matugen"),
                 os.path.expanduser("~/.local/bin/matugen")):
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


MATUGEN = _find_matugen()


def main():
    if MATUGEN is None:
        print("matugen no encontrado (instala matugen o define $MATUGEN).")
        sys.exit(1)
    # matugen no crea el directorio de salida de las plantillas.
    os.makedirs(CACHE_DIR, exist_ok=True)
    r, g, b = get_accent_rgb()
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    accent = hsv_to_hex(h, s, v)

    proc = subprocess.run(
        [MATUGEN, "color", "hex", accent, "-t", "scheme-fidelity",
         "-m", "dark", "-j", "hex"],
        capture_output=True, text=True, timeout=30,
    )
    if proc.returncode != 0:
        print(f"matugen falló: {proc.stderr.strip()[:300]}")
        sys.exit(1)
    # Escribe colors.json INMEDIATAMENTE tras matugen, antes de cualquier otro
    # paso (cava, millennium, hooks legacy, etc.) para que la shell recargue
    # los colores tan pronto como matugen termine.
    colors_path = os.path.join(CACHE_DIR, "colors.json")
    try:
        fd, tmp_path = tempfile.mkstemp(dir=CACHE_DIR, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(proc.stdout)
        os.replace(tmp_path, colors_path)
    except OSError as e:
        print(f"no se pudo escribir colors.json: {e}")
    mc = _matugen_dark(proc.stdout, accent)

    try:
        inject_cava()
    except Exception as e:
        print(f"cava: no se pudo inyectar: {e}")
    try:
        sync_millennium(accent)
    except Exception as e:
        print(f"millennium: {e}")
    try:
        run_legacy_hooks(_hook_env(accent, mc))
    except Exception as e:
        print(f"hooks: {e}")

    # Recargas en vivo que matugen no puede hacer solo:
    # kitty: aplica theme.conf en todos los sockets
    kitty_theme = os.path.expanduser("~/.config/kitty/theme.conf")
    try:
        import glob
        for sock in glob.glob("/tmp/kitty-socket-*"):
            try:
                subprocess.run(
                    ["kitty", "@", "--to", f"unix:{sock}",
                     "set-colors", "-a", kitty_theme],
                    check=True, timeout=3,
                    capture_output=True)
            except Exception:
                pass
    except Exception:
        pass
    # ghostty: toca config para recarga en vivo
    try:
        pathlib.Path(os.path.expanduser("~/.config/ghostty/config")).touch()
    except OSError:
        pass
    # zen: copia el css matugen a cada perfil + asegura import/user.js
    try:
        deploy_zen()
    except Exception as e:
        print(f"zen: no se pudo desplegar: {e}")


def _matugen_dark(stdout, accent):
    import json
    mc = {"accent": accent}
    try:
        data = json.loads(stdout)
        colors = data.get("colors", {})
        def g(key, fb):
            try:
                return colors[key]["dark"]["color"]
            except (KeyError, TypeError):
                return fb
        mc.update({
            "bg": g("background", accent),
            "card": g("surface_variant", accent),
            "fg": g("on_secondary_container", "#f1dede"),
            "primary": g("primary", accent),
            "secondary": g("secondary", accent),
            "tertiary": g("tertiary", accent),
            "secondary_container": g("secondary_container", accent),
            "outline": g("outline", accent),
        })
    except (ValueError, AttributeError):
        mc.update({"bg": accent, "card": accent, "fg": "#f1dede",
                   "primary": accent, "secondary": accent,
                   "tertiary": accent, "outline": accent})
    return mc


def _hook_env(accent, mc):
    env = dict(os.environ)
    env.update({
        "MATUGEN_ACCENT": accent,
        "MATUGEN_BG": mc["bg"],
        "MATUGEN_CARD": mc["card"],
        "MATUGEN_FG": mc["fg"],
        "MATUGEN_PRIMARY": mc["primary"],
        "MATUGEN_SECONDARY": mc["secondary"],
        "MATUGEN_TERTIARY": mc["tertiary"],
        "MATUGEN_OUTLINE": mc["outline"],
        "MATUGEN_BG_OVER": mc["card"],
        "MATUGEN_BG_OVER2": mc["outline"],
        "MATUGEN_GREY": mc["outline"],
        "MATUGEN_ACCENT_LIGHT": mc["primary"],
        "MATUGEN_ACCENT_PRESSED": mc["secondary_container"],
    })
    return env


LEGACY_HOOKS = [
    "~/.config/equibop/generate_equibop_theme.py",
    "~/.config/kitty/generate_gnome_accent.py",
    "~/.config/kitty/generate_brave_theme.py",
    "~/.config/kitty/generate_obs_theme.py",
    "~/.config/kitty/generate_materialgram_theme.py",
    "~/.config/kitty/generate_nothingisland_theme.py",
    "~/.config/kitty/generate_gamedrawer_theme.py",
    "~/.config/kitty/generate_wallpaperdrawer_theme.py",
    "~/.config/kitty/generate_wallpapereffects_theme.py",
    "~/.config/kitty/generate_caelestia_theme.py",
    "~/.config/kitty/generate_noctalia_theme.py",
]


def run_legacy_hooks(env):
    for hook in LEGACY_HOOKS:
        path = os.path.expanduser(hook)
        if not os.path.exists(path):
            continue
        try:
            proc = subprocess.run(
                [sys.executable, path],
                capture_output=True, text=True, timeout=180, env=env)
            out = (proc.stdout or "").strip().replace("\n", " | ")[:300]
            print(f"hook {os.path.basename(path)}: exit={proc.returncode} {out}")
        except Exception as e:
            print(f"hook {hook}: {e}")


def sync_millennium(accent):
    import json as _json
    import tempfile
    cfg_path = os.path.expanduser("~/.config/millennium/config.json")
    if not os.path.exists(cfg_path):
        print("millennium: no encontrado, salto.")
        return
    with open(cfg_path, encoding="utf-8") as f:
        cfg = _json.load(f)
    changed = []
    general = cfg.setdefault("general", {})
    if general.get("accentColor") != accent:
        general["accentColor"] = accent
        changed.append("general.accentColor")
    entry = cfg.setdefault("themes", {}).setdefault("themeColors", {}).setdefault("Material-Theme", {})
    if entry.get("--custom-accent-color") != accent:
        entry["--custom-accent-color"] = accent
        changed.append("themeColors.Material-Theme")
    if changed:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(cfg_path), suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                _json.dump(cfg, f, indent=2)
                f.write("\n")
            os.replace(tmp, cfg_path)
        except OSError:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            return
    txt = os.path.expanduser("~/.config/millennium/dinamico-accent.txt")
    try:
        old = open(txt, encoding="utf-8").read().strip() if os.path.exists(txt) else None
        if old != accent:
            with open(txt, "w", encoding="utf-8") as f:
                f.write(accent + "\n")
    except OSError:
        pass
    print(f"millennium: {', '.join(changed) if changed else 'ya estaba'} en {accent}.")


def inject_cava():
    import re
    snippet = os.path.expanduser("~/.cache/matugen-cava-snippet")
    cava_cfg = os.path.expanduser("~/.config/cava/config")
    if not os.path.exists(snippet) or not os.path.exists(cava_cfg):
        return
    wanted = {}
    with open(snippet, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, val = [x.strip() for x in line.split("=", 1)]
            wanted[k] = val
    if not wanted:
        return
    with open(cava_cfg, encoding="utf-8") as f:
        lines = f.readlines()
    lines = ensure_key(lines, "general", "live-config", "1")
    for k, val in wanted.items():
        lines = ensure_key(lines, "color", k, val)
    with open(cava_cfg, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"cava: snippet matugen inyectado ({len(wanted)} claves).")


def ensure_key(lines, section, key, value):
    import re
    out, in_section, found_section, done = [], False, False, False
    pat = re.compile(rf"^[;\s#]*{re.escape(key)}\s*=")
    sec_pat = re.compile(r"^\s*\[([^\]]+)\]")
    for line in lines:
        m = sec_pat.match(line)
        if m:
            if in_section and not done:
                out.append(f"{key} = {value}\n")
                done = True
            in_section = (m.group(1).strip() == section)
            if in_section:
                found_section = True
            out.append(line)
            continue
        if in_section and pat.match(line):
            if not done:
                out.append(f"{key} = {value}\n")
                done = True
            continue
        out.append(line)
    if not found_section:
        out.append(f"\n[{section}]\n{key} = {value}\n")
    elif not done:
        idx = None
        for i, line in enumerate(out):
            if sec_pat.match(line) and line.strip() == f"[{section}]":
                idx = i
        if idx is None:
            out.append(f"{key} = {value}\n")
            return out
        insert_at = len(out)
        for i in range(idx + 1, len(out)):
            if sec_pat.match(out[i]):
                insert_at = i
                break
        out.insert(insert_at, f"{key} = {value}\n")
    return out


def deploy_zen():
    import glob as _glob
    import shutil
    src = os.path.expanduser("~/.cache/matugen-zen-kde-accent.css")
    if not os.path.exists(src):
        return
    roots = []
    roots += _glob.glob(os.path.expanduser("~/.var/app/app.zen_browser.zen/.zen/*.Default*"))
    roots += _glob.glob(os.path.expanduser("~/.zen/*.Default*"))
    roots = [d for d in roots if os.path.isdir(d)]
    if not roots:
        print("zen: sin perfiles, salto copia.")
        return
    for profile in roots:
        chrome = os.path.join(profile, "chrome")
        os.makedirs(chrome, exist_ok=True)
        shutil.copyfile(src, os.path.join(chrome, "kde-accent.css"))
        _zen_ensure_import(os.path.join(chrome, "userChrome.css"))
        _zen_ensure_userjs(profile)
        print(f"zen [{os.path.basename(profile)}]: kde-accent.css actualizado.")


def _zen_ensure_import(userchrome):
    line = '@import url("kde-accent.css");'
    if not os.path.exists(userchrome):
        with open(userchrome, "w") as f:
            f.write("/* Generado por accent_to_matugen.py — no editar la línea de import */\n" + line + "\n")
        return
    with open(userchrome) as f:
        if "kde-accent.css" in f.read():
            return
    with open(userchrome, "a") as f:
        f.write("\n" + line + "\n")


def _zen_ensure_userjs(profile):
    userjs = os.path.join(profile, "user.js")
    pref = 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
    if os.path.exists(userjs):
        with open(userjs) as f:
            if "legacyUserProfileCustomizations" in f.read():
                return
    with open(userjs, "a") as f:
        f.write("\n// Añadido por accent_to_matugen.py\n" + pref + "\n")


if __name__ == "__main__":
    main()

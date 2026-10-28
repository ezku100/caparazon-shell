#!/usr/bin/env bash
# Vigila kdeglobals y regenera los temas cuando cambia el AccentColor de KDE.
# Portable: no depende de Waywallen ni de rutas absolutas del usuario.

CONFIG_DIR="$HOME/.config"
TARGET_FILE="kdeglobals"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYWALLEN_CONF="$HOME/.var/app/org.waywallen.waywallen/config/waywallen/config.toml"
WAYWALLEN_DERIVER="$SCRIPT_DIR/derive_waywallen_accent.py"
MATUGEN_FEEDER="$SCRIPT_DIR/accent_to_matugen.py"
CACHE_DIR="$HOME/.cache/caparazon"
LAST_ACCENT_FILE="$CACHE_DIR/last-watch-accent"
FEEDER_LOCK="$CACHE_DIR/feeder.lock"

if ! command -v inotifywait >/dev/null 2>&1; then
    echo "watch_accent: falta inotifywait (paquete inotify-tools)." >&2
    exit 1
fi

current_accent() {
    if command -v kreadconfig6 >/dev/null 2>&1; then
        kreadconfig6 --file kdeglobals --group General --key AccentColor 2>/dev/null || true
    elif command -v kreadconfig5 >/dev/null 2>&1; then
        kreadconfig5 --file kdeglobals --group General --key AccentColor 2>/dev/null || true
    else
        python3 -c 'import configparser,os
c = configparser.ConfigParser(strict=False)
c.read(os.path.expanduser("~/.config/kdeglobals"))
print(c.get("General", "AccentColor", fallback=""))' 2>/dev/null || true
    fi
}

WATCH_DIRS=("$CONFIG_DIR")
if [[ -d "$(dirname "$WAYWALLEN_CONF")" ]]; then
    WATCH_DIRS+=("$(dirname "$WAYWALLEN_CONF")")
fi

mkdir -p "$CACHE_DIR"
echo "Vigilando AccentColor en ${WATCH_DIRS[*]} ..."

inotifywait -m -e modify,close_write,moved_to --format '%w%f' "${WATCH_DIRS[@]}" |
while read -r path; do
    if [[ "$path" == "$WAYWALLEN_CONF" ]]; then
        sleep 0.5
        python3 "$WAYWALLEN_DERIVER" 2>&1 | head -n 2
        continue
    fi
    if [[ "$(basename "$path")" != "$TARGET_FILE" ]]; then
        continue
    fi
    sleep 0.5
    cur="$(current_accent)"
    last=""
    [[ -f "$LAST_ACCENT_FILE" ]] && last="$(cat "$LAST_ACCENT_FILE" 2>/dev/null)"
    if [[ -n "$cur" && "$cur" == "$last" ]]; then
        continue
    fi
    if flock -n "$FEEDER_LOCK" python3 "$MATUGEN_FEEDER"; then
        printf '%s' "$cur" > "$LAST_ACCENT_FILE"
    else
        echo "feeder ya en curso, se reintenta con el siguiente evento"
    fi
done

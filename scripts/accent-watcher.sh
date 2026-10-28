#!/bin/bash
# Caparazon — vigila el AccentColor de KDE y regenera ~/.cache/caparazon/colors.json
# con matugen para que la shell cambie de tema al instante.
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/caparazon"
COLORS_JSON="$CACHE_DIR/colors.json"
LAST_ACCENT="$CACHE_DIR/last-accent"

mkdir -p "$CACHE_DIR"

current_accent() {
    if command -v kreadconfig6 >/dev/null 2>&1; then
        kreadconfig6 --file "$HOME/.config/kdeglobals" --group General --key AccentColor 2>/dev/null || true
    elif command -v kreadconfig5 >/dev/null 2>&1; then
        kreadconfig5 --file "$HOME/.config/kdeglobals" --group General --key AccentColor 2>/dev/null || true
    fi
}

while true; do
    cur="$(current_accent)"
    last=""
    [ -f "$LAST_ACCENT" ] && last="$(cat "$LAST_ACCENT" 2>/dev/null || true)"

    if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
        if matugen color hex "$cur" -t scheme-fidelity -m dark -j hex \
                > "$COLORS_JSON.tmp" 2>/dev/null; then
            mv "$COLORS_JSON.tmp" "$COLORS_JSON"
            printf '%s' "$cur" > "$LAST_ACCENT"
        fi
    fi

    sleep 2
done

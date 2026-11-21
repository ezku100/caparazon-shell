#!/bin/bash
# Ejecuta un comando IPC de la shell (menu, menu2, power).
#
# La ruta de la shell viva no es fija: install.sh la deja en
# ~/.config/quickshell/caparazon, pero un clon anterior puede seguir
# arrancándose desde su propio directorio. Por eso se lee la ruta real
# del lanzador de arranque automático y, si no hay, se usa la de XDG.
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
AUTOSTART_FILE="$CONFIG_HOME/autostart/caparazon.desktop"
FALLBACK_SHELL_DIR="$CONFIG_HOME/quickshell/caparazon"

shell_dir() {
    if [ -r "$AUTOSTART_FILE" ]; then
        local detected
        detected="$(sed -n 's|.*quickshell -p \([^ ]*\).*|\1|p' "$AUTOSTART_FILE" | head -n 1)"
        if [ -n "$detected" ] && [ -f "$detected/shell.qml" ]; then
            printf '%s\n' "$detected"
            return 0
        fi
    fi
    if [ -f "$FALLBACK_SHELL_DIR/shell.qml" ]; then
        printf '%s\n' "$FALLBACK_SHELL_DIR"
        return 0
    fi
    return 1
}

if [ "$#" -eq 0 ]; then
    echo "uso: caparazon-shell-ipc <menu|menu2|power> <abrir|cerrar|alternar> [categoria]" >&2
    exit 2
fi

target_dir="$(shell_dir || true)"
if [ -z "$target_dir" ]; then
    echo "caparazon-shell-ipc: no encuentro la shell de Caparazon" >&2
    echo "  revisado: $AUTOSTART_FILE" >&2
    echo "  revisado: $FALLBACK_SHELL_DIR" >&2
    exit 1
fi

exec quickshell -p "$target_dir" ipc call "$@"

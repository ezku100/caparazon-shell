#!/bin/bash
# Ejecuta un comando IPC de la shell (menu, menu2, power).
#
# La ruta de la shell viva no es fija: install.sh la deja en
# ~/.config/quickshell/caparazon, pero un clon anterior puede seguir
# arrancándose desde su propio directorio. La busca caparazon-shell-path.sh,
# que mira primero la unit systemd que la arranca y, si no hay, el arranque
# automático antiguo.
set -euo pipefail

SELF="$(command -v "$0" 2>/dev/null || printf '%s' "$0")"
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
HELPER="$SELF_DIR/caparazon-shell-path.sh"
if [ ! -x "$HELPER" ]; then
    HELPER="$(command -v caparazon-shell-path 2>/dev/null || true)"
fi

if [ -z "$HELPER" ] || [ ! -x "$HELPER" ]; then
    echo "caparazon-shell-ipc: no encuentro caparazon-shell-path.sh" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    echo "uso: caparazon-shell-ipc <menu|menu2|power> <abrir|cerrar|alternar> [categoria]" >&2
    exit 2
fi

target_dir="$("$HELPER" || true)"
if [ -z "$target_dir" ]; then
    echo "caparazon-shell-ipc: no encuentro la shell de Caparazon" >&2
    echo "  revisado: ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/caparazon-shell.service" >&2
    echo "  revisado: ${XDG_CONFIG_HOME:-$HOME/.config}/autostart/caparazon.desktop" >&2
    exit 1
fi

exec quickshell -p "$target_dir" ipc call "$@"

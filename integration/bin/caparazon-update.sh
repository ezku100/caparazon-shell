#!/bin/bash
# Actualiza la shell: pull --ff-only, reinstala y reinicia quickshell.
# Uso: caparazon-update.sh <repo> <shell> [rama]
#
# Se lanza desde una unidad transitoria (systemd-run --user) para que el
# reinicio de la shell no mate al propio actualizador. Todo queda en
# ~/.cache/caparazon/update.log.
#
# Códigos: 2 cambios locales, 3 sin repositorio, 4 el pull falló.
set -u

repo=${1:-}
shell=${2:-}
branch=${3:-main}

log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/caparazon"
mkdir -p "$log_dir"
log="$log_dir/update.log"
exec >>"$log" 2>&1

echo "[$(date -Is)] actualizar $repo ($branch) -> $shell"

if [ -z "$repo" ] || [ ! -d "$repo/.git" ]; then
    echo "sin repositorio en $repo"
    exit 3
fi

export GIT_TERMINAL_PROMPT=0

if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "cambios locales sin commit; no se toca nada"
    exit 2
fi

if ! git -C "$repo" pull --ff-only origin "$branch"; then
    echo "el pull falló"
    exit 4
fi

if [ -x "$repo/install.sh" ]; then
    if ! "$repo/install.sh"; then
        echo "install.sh falló; la shell se reinicia con lo que haya"
    fi
fi

if systemctl --user restart app-caparazon@autostart.service 2>/dev/null; then
    echo "shell reiniciada por systemd"
    exit 0
fi

if [ -n "$shell" ]; then
    pkill -f "quickshell -p $shell" 2>/dev/null
    sleep 0.5
    setsid quickshell -p "$shell" -d >/dev/null 2>&1 &
    echo "shell relanzada a mano"
fi

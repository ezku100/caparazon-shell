#!/bin/bash
# ¿Hay commits nuevos en el remoto? Imprime una sola línea para la shell:
#   uptodate | available <n> clean | available <n> dirty | offline | norepo
#
# Sólo cuenta cambios en archivos rastreados: los artefactos sin seguimiento
# (__pycache__, etc.) no bloquean una actualización. Sin red no falla.
set -u

repo=${1:-}
branch=${2:-main}

if [ -z "$repo" ] || [ ! -d "$repo/.git" ]; then
    echo "norepo"
    exit 0
fi

export GIT_TERMINAL_PROMPT=0

if ! git -C "$repo" fetch --quiet origin "$branch" 2>/dev/null; then
    echo "offline"
    exit 0
fi

behind=$(git -C "$repo" rev-list --count "HEAD..origin/$branch" 2>/dev/null) || behind=0
if [ "$behind" -le 0 ] 2>/dev/null; then
    echo "uptodate"
    exit 0
fi

if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "available $behind dirty"
else
    echo "available $behind clean"
fi

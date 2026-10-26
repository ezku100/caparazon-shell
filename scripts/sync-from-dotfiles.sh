#!/usr/bin/env bash
# Sincroniza este repositorio con la copia de trabajo del repo de dotfiles.
#
#   DOTFILES_DIR=~/dotfiles ./scripts/sync-from-dotfiles.sh "mensaje del commit"
#
# Copia quickshell/caparazon (fuente de verdad en dotfiles) hacia este repo,
# deja un commit y lo sube. Sin argumentos no hace commit ni push.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
SRC="$DOTFILES_DIR/quickshell/caparazon"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$SRC/shell.qml" ]]; then
    echo "No encuentro la shell en $SRC" >&2
    echo "Define DOTFILES_DIR con la ruta de tu repo de dotfiles." >&2
    exit 1
fi

echo "Sincronizando $SRC -> $REPO"
for item in shell.qml modules theme components assets; do
    rm -rf "$REPO/$item"
    cp -r "$SRC/$item" "$REPO/$item"
done

if [[ -z "$(git -C "$REPO" status --porcelain)" ]]; then
    echo "No habia cambios."
    exit 0
fi

git -C "$REPO" status --short

if [[ $# -gt 0 ]]; then
    git -C "$REPO" add -A
    git -C "$REPO" commit -m "$1"
    echo "Commit hecho. Para subirlo: git -C $REPO push"
fi

#!/usr/bin/env bash
# Caparazon — instalador de la shell de escritorio.
#
#   ./install.sh              instala la shell, el puente de escritorios y el
#                             arranque automatico
#   ./install.sh desinstalar  quita lo que instalo este script
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SHELL_DIR="$CONFIG_HOME/quickshell/caparazon"
AUTOSTART_DIR="$CONFIG_HOME/autostart"
BIN_DIR="$HOME/.local/bin"
KWIN_DIR="$HOME/.local/share/kwin/scripts/ezkudesktops/contents/code"

usage() {
    cat <<EOF
Uso: $(basename "$0") [instalar|desinstalar]

  instalar     Copia la shell a $SHELL_DIR, instala el puente de
               escritorios y registra el arranque automatico.
  desinstalar  Quita lo que instalo este script.
EOF
}

require_quickshell() {
    if ! command -v quickshell >/dev/null 2>&1; then
        echo "AVISO: quickshell no esta en el PATH." >&2
        echo "       En PikaOS: sudo apt install quickshell" >&2
        echo "       Continuando con la instalacion de archivos." >&2
    fi
}

install_shell() {
    echo "Instalando la shell en $SHELL_DIR"
    mkdir -p "$SHELL_DIR"
    cp -r "$REPO/shell.qml" "$REPO/modules" "$REPO/theme" \
        "$REPO/components" "$REPO/assets" "$SHELL_DIR/"
}

install_bridge() {
    echo "Instalando el puente de escritorios"
    mkdir -p "$BIN_DIR" "$KWIN_DIR"
    install -m755 "$REPO/integration/bin/ezku-desktops-bootstrap.sh" "$BIN_DIR/"
    install -m755 "$REPO/integration/bin/ezku-desktops-daemon.py" "$BIN_DIR/"
    install -m644 \
        "$REPO/integration/kwin/ezkudesktops/contents/code/main.js" \
        "$KWIN_DIR/main.js"
}

install_autostart() {
    echo "Registrando el arranque automatico"
    mkdir -p "$AUTOSTART_DIR"
    sed -e "s|@SHELL_PATH@|$SHELL_DIR|g" \
        "$REPO/integration/autostart/caparazon.desktop.in" \
        > "$AUTOSTART_DIR/caparazon.desktop"
    sed -e "s|@HOME@|$HOME|g" \
        "$REPO/integration/autostart/ezku-desktops-bridge.desktop.in" \
        > "$AUTOSTART_DIR/ezku-desktops-bridge.desktop"
}

uninstall() {
    echo "Quitando Caparazon"
    rm -rf "$SHELL_DIR"
    rm -f "$AUTOSTART_DIR/caparazon.desktop"
    rm -f "$AUTOSTART_DIR/ezku-desktops-bridge.desktop"
    rm -f "$BIN_DIR/ezku-desktops-bootstrap.sh"
    rm -f "$BIN_DIR/ezku-desktops-daemon.py"
    rm -rf "$HOME/.local/share/kwin/scripts/ezkudesktops"
    echo "Listo. El proceso de Quickshell sigue vivo: cierralo con"
    echo "  pkill -f 'quickshell -p $SHELL_DIR'"
}

case "${1:-instalar}" in
    instalar)
        require_quickshell
        install_shell
        install_bridge
        install_autostart
        echo
        echo "Listo. Para probarla ahora mismo:"
        echo "  quickshell -p $SHELL_DIR"
        echo
        echo "En el siguiente inicio de sesion arrancara sola."
        ;;
    desinstalar)
        uninstall
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac

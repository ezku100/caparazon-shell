#!/bin/bash
# Caparazon — instalador de la shell de escritorio.
#
#   ./install.sh              instala la shell, el puente de escritorios, el
#                             arranque automatico y el tema accent-theme
#   ./install.sh desinstalar  quita lo que instalo este script
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
SHELL_DIR="$CONFIG_HOME/quickshell/caparazon"
AUTOSTART_DIR="$CONFIG_HOME/autostart"
BIN_DIR="$HOME/.local/bin"
KWIN_DIR="$HOME/.local/share/kwin/scripts/ezkudesktops/contents/code"

ACCENT_THEME_REPO="${ACCENT_THEME_REPO:-https://github.com/ezku100/accent-theme.git}"
ACCENT_THEME_SOURCE="${ACCENT_THEME_SOURCE:-$DATA_HOME/accent-theme/source}"
ACCENT_THEME_BIN="$BIN_DIR/accent-theme"
ACCENT_THEME_DESCRIPTOR="$REPO/integration/theme/accent-theme.toml"
ACCENT_THEME_TOKENS="$REPO/integration/theme/required-tokens.txt"
ACCENT_THEME_TEMPLATE_DIR="$CONFIG_HOME/accent-theme/templates/caparazon-shell"
ACCENT_THEME_INSTALLED_DESCRIPTOR="$CONFIG_HOME/accent-theme/templates.d/caparazon-shell.toml"
ACCENT_THEME_PALETTE="$HOME/.cache/caparazon/colors.json"
REQUIRED_THEME_DEPENDENCIES=(matugen python3 inotifywait flock kreadconfig6 git)
THEME_APT_PACKAGES="matugen python3 inotify-tools util-linux libkf6config-bin git"
MENU_SHORTCUT_ID="net.local.quickshell-2"
MENU_SHORTCUT_KEY="Meta"
MENU_SHORTCUT_SECTION="[services][${MENU_SHORTCUT_ID}.desktop]"
MENU_SHORTCUT_PATTERN="^\[services\]\[${MENU_SHORTCUT_ID//./\\.}\.desktop\]$"

usage() {
    cat <<EOF
Uso: $(basename "$0") [instalar|desinstalar]

  instalar     Copia la shell a $SHELL_DIR, instala el puente de
               escritorios, registra el arranque automatico y conecta el
               tema accent-theme con la paleta dinamica.
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

require_theme_dependencies() {
    local missing=()
    local dependency
    for dependency in "${REQUIRED_THEME_DEPENDENCIES[@]}"; do
        command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "ERROR: faltan dependencias del tema: ${missing[*]}" >&2
        echo "       En PikaOS: sudo apt install $THEME_APT_PACKAGES" >&2
        exit 1
    fi
}

install_shell() {
    echo "Instalando la shell en $SHELL_DIR"
    if [ -d "$REPO/.git" ]; then
        echo "Actualizando el repositorio local"
        git -C "$REPO" pull --ff-only
    fi
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

existing_shell_dir() {
    local autostart="$AUTOSTART_DIR/caparazon.desktop"
    local path
    [ -f "$autostart" ] || return 1
    path="$(sed -n 's/.*quickshell -p \([^ ]*\).*/\1/p' "$autostart" | head -n 1)"
    [ -n "$path" ] || return 1
    [ -f "$path/shell.qml" ] || return 1
    printf '%s\n' "$path"
}

install_shortcut() {
    local shell_path="$1"
    local applications="$DATA_HOME/applications"
    local desktop="$applications/$MENU_SHORTCUT_ID.desktop"
    echo "Instalando el atajo global del menu"
    mkdir -p "$applications"
    sed -e "s|@SHELL_PATH@|$shell_path|g" \
        "$REPO/integration/shortcuts/caparazon-menu.desktop.in" \
        > "$desktop"
    chmod 644 "$desktop"
    bind_shortcut_key
    refresh_service_cache
}

refresh_service_cache() {
    local builder
    for builder in kbuildsycoca6 kbuildsycoca5; do
        if command -v "$builder" >/dev/null 2>&1; then
            "$builder" --noincremental >/dev/null 2>&1 || true
            return 0
        fi
    done
}

refresh_shortcut_hint() {
    if pgrep -x kwin_wayland >/dev/null 2>&1; then
        echo "       El atajo global se activa al reiniciar el compositor"
        echo "       (o al cerrar y abrir la sesion)."
    fi
}

bind_shortcut_key() {
    local file="$CONFIG_HOME/kglobalshortcutsrc"
    mkdir -p "$CONFIG_HOME"
    touch "$file"
    if grep -qF "$MENU_SHORTCUT_SECTION" "$file"; then
        sed -i "/$MENU_SHORTCUT_PATTERN/,/^\[/ s|^_launch=.*|_launch=$MENU_SHORTCUT_KEY|" \
            "$file"
    else
        printf '\n%s\n_launch=%s\n' "$MENU_SHORTCUT_SECTION" "$MENU_SHORTCUT_KEY" \
            >> "$file"
    fi
}

remove_shortcut() {
    rm -f "$DATA_HOME/applications/$MENU_SHORTCUT_ID.desktop"
    local file="$CONFIG_HOME/kglobalshortcutsrc"
    if [ ! -f "$file" ]; then
        return 0
    fi
    sed -i "/$MENU_SHORTCUT_PATTERN/,/^\[/ s|^_launch=.*|_launch=none|" "$file"
}

fetch_theme_engine() {
    echo "Obteniendo el motor accent-theme"
    if [ -d "$ACCENT_THEME_SOURCE/.git" ]; then
        git -C "$ACCENT_THEME_SOURCE" pull --ff-only
    elif [ -d "$ACCENT_THEME_SOURCE" ]; then
        echo "       usando el checkout local $ACCENT_THEME_SOURCE"
    else
        mkdir -p "$(dirname "$ACCENT_THEME_SOURCE")"
        case "$ACCENT_THEME_REPO" in
            http*) git clone --depth 1 "$ACCENT_THEME_REPO" "$ACCENT_THEME_SOURCE" ;;
            *) git clone "$ACCENT_THEME_REPO" "$ACCENT_THEME_SOURCE" ;;
        esac
    fi
}

install_theme_engine() {
    echo "Instalando el motor accent-theme"
    bash "$ACCENT_THEME_SOURCE/install.sh" instalar
}

register_caparazon_theme() {
    echo "Registrando la plantilla de Caparazon"
    "$ACCENT_THEME_BIN" register --app caparazon-shell \
        --descriptor "$ACCENT_THEME_DESCRIPTOR"
    "$ACCENT_THEME_BIN" generate
}

link_xdg_cache() {
    if [ "$CACHE_HOME" = "$HOME/.cache" ]; then
        return 0
    fi
    mkdir -p "$CACHE_HOME" "$HOME/.cache/caparazon"
    if [ -L "$CACHE_HOME/caparazon" ]; then
        rm -f "$CACHE_HOME/caparazon"
    elif [ -e "$CACHE_HOME/caparazon" ]; then
        echo "AVISO: $CACHE_HOME/caparazon ya existe y no es un enlace." >&2
        echo "       Enlaza a mano si lo quieres usar: $HOME/.cache/caparazon" >&2
        return 0
    fi
    ln -s "$HOME/.cache/caparazon" "$CACHE_HOME/caparazon"
}

validate_palette() {
    local palette="$ACCENT_THEME_PALETTE"
    local missing_tokens=""
    local token
    if [ ! -f "$palette" ]; then
        echo "ERROR: el motor no genero $palette" >&2
        return 1
    fi
    while read -r token || [ -n "$token" ]; do
        [ -z "$token" ] && continue
        if ! grep -q "\"$token\"" "$palette"; then
            missing_tokens="$missing_tokens $token"
        fi
    done < "$ACCENT_THEME_TOKENS"
    if [ -n "$missing_tokens" ]; then
        echo "ERROR: la paleta no contiene:$missing_tokens" >&2
        return 1
    fi
    echo "Paleta validada en $palette"
}

install_theme() {
    echo "Conectando el tema accent-theme"
    require_theme_dependencies
    fetch_theme_engine
    install_theme_engine
    register_caparazon_theme
    link_xdg_cache
    validate_palette
}

remove_caparazon_theme() {
    rm -f "$ACCENT_THEME_INSTALLED_DESCRIPTOR"
    rm -rf "$ACCENT_THEME_TEMPLATE_DIR"
    rm -f "$ACCENT_THEME_PALETTE"
    if [ -L "$CACHE_HOME/caparazon" ]; then
        rm -f "$CACHE_HOME/caparazon"
    fi
}

uninstall_theme() {
    remove_caparazon_theme
    if [ ! -f "$ACCENT_THEME_SOURCE/install.sh" ]; then
        return 0
    fi
    echo "Desinstalando el motor accent-theme"
    bash "$ACCENT_THEME_SOURCE/install.sh" desinstalar
}

uninstall() {
    echo "Quitando Caparazon"
    rm -rf "$SHELL_DIR"
    rm -f "$AUTOSTART_DIR/caparazon.desktop"
    rm -f "$AUTOSTART_DIR/ezku-desktops-bridge.desktop"
    rm -f "$BIN_DIR/ezku-desktops-bootstrap.sh"
    rm -f "$BIN_DIR/ezku-desktops-daemon.py"
    rm -rf "$HOME/.local/share/kwin/scripts/ezkudesktops"
    remove_shortcut
    uninstall_theme
    echo "Listo. El proceso de Quickshell sigue vivo: cierralo con"
    echo "  pkill -f 'quickshell -p $SHELL_DIR'"
}

case "${1:-instalar}" in
    instalar)
        require_quickshell
        EXISTING_SHELL_DIR="$(existing_shell_dir || true)"
        if [ -n "$EXISTING_SHELL_DIR" ] && [ "$EXISTING_SHELL_DIR" != "$SHELL_DIR" ]; then
            echo "Reutilizando la shell de $EXISTING_SHELL_DIR"
            echo "No se crea una copia en $SHELL_DIR ni se toca el arranque automatico"
            ACTIVE_SHELL_DIR="$EXISTING_SHELL_DIR"
        else
            install_shell
            install_autostart
            ACTIVE_SHELL_DIR="$SHELL_DIR"
        fi
        install_shortcut "$ACTIVE_SHELL_DIR"
        refresh_shortcut_hint
        install_bridge
        install_theme
        echo
        echo "Listo. Para probarla ahora mismo:"
        echo "  quickshell -p $ACTIVE_SHELL_DIR"
        echo
        echo "En el siguiente inicio de sesion arrancara sola."
        echo "Atajo global: $MENU_SHORTCUT_KEY abre el menu central."
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

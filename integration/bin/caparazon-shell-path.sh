#!/bin/bash
# Devuelve la ruta de la carpeta de la shell viva de Caparazón.
#
# La ruta no es fija: install.sh la deja en ~/.config/quickshell/caparazon,
# pero una instalación existente puede arrancarse desde su propio clon.
# Desde que la shell arranca como servicio, la fuente de verdad es la unit
# caparazon-shell.service; el .desktop de autostart queda como compatibilidad
# con las instalaciones anteriores a ese cambio.
set -u

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SYSTEMD_UNIT="$CONFIG_HOME/systemd/user/caparazon-shell.service"
AUTOSTART_FILE="$CONFIG_HOME/autostart/caparazon.desktop"
FALLBACK_SHELL_DIR="$CONFIG_HOME/quickshell/caparazon"

# Del lanzador (scripts/caparazon-shell) sale la carpeta de la shell.
shell_root_from_launcher() {
    local launcher="$1" detected
    [ -n "$launcher" ] || return 1
    [ -f "$launcher" ] || return 1
    detected="$(cd "$(dirname "$launcher")/.." && pwd)"
    [ -f "$detected/shell.qml" ] || return 1
    printf '%s\n' "$detected"
}

# 1. La unit instalada: su ExecStart apunta al lanzador.
if [ -r "$SYSTEMD_UNIT" ]; then
    launcher="$(sed -n 's|^ExecStart=||p' "$SYSTEMD_UNIT" | head -n 1)"
    detected="$(shell_root_from_launcher "$launcher" || true)"
    if [ -n "$detected" ]; then
        printf '%s\n' "$detected"
        exit 0
    fi
fi

# 2. systemd en vivo: la unit puede estar fuera de XDG o haber cambiado.
if command -v systemctl >/dev/null 2>&1; then
    exec_start="$(systemctl --user show caparazon-shell.service \
        -p ExecStart --value 2>/dev/null || true)"
    launcher="$(printf '%s\n' "$exec_start" \
        | sed -n 's|.*path=\([^ ;]*\).*|\1|p' | head -n 1)"
    detected="$(shell_root_from_launcher "$launcher" || true)"
    if [ -n "$detected" ]; then
        printf '%s\n' "$detected"
        exit 0
    fi
fi

# 3. Autostart antiguo (instalaciones previas al servicio).
if [ -r "$AUTOSTART_FILE" ]; then
    detected="$(sed -n 's|.*quickshell -p \([^ ]*\).*|\1|p' "$AUTOSTART_FILE" \
        | head -n 1)"
    if [ -n "$detected" ] && [ -f "$detected/shell.qml" ]; then
        printf '%s\n' "$detected"
        exit 0
    fi
    launcher="$(sed -n 's|^Exec=[[:space:]]*\([^ ]*/scripts/caparazon-shell\)[[:space:]]*$|\1|p' \
        "$AUTOSTART_FILE" | head -n 1)"
    detected="$(shell_root_from_launcher "$launcher" || true)"
    if [ -n "$detected" ]; then
        printf '%s\n' "$detected"
        exit 0
    fi
fi

# 4. Ruta por defecto de XDG.
if [ -f "$FALLBACK_SHELL_DIR/shell.qml" ]; then
    printf '%s\n' "$FALLBACK_SHELL_DIR"
    exit 0
fi

exit 1

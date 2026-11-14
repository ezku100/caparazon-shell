#!/bin/bash
# Caparazón — guardián del render.
#
# Cuando el driver gráfico se queda sin memoria, Quickshell pierde el
# contexto GL ("Graphics device lost, cleaning up scenegraph and releasing
# RHI"). El proceso sigue vivo, así que systemd no lo reinicia, pero algunas
# superficies dejan de pintarse: por ejemplo el cristal de la barra
# desaparece y sólo quedan los iconos flotando.
#
# Este vigilante lee el log de la instancia activa y reinicia la shell en
# cuanto aparece la pérdida de contexto. Cada arranque de Quickshell crea un
# directorio nuevo en `quickshell/by-id`, así que el log se resuelve por el
# PID vivo (`quickshell/by-pid/<pid>`) cada pocos segundos. Vive en el
# arranque automático del usuario y no escribe nada en disco.
set -u

SERVICE="${CAPARAZON_SERVICE:-app-caparazon@autostart.service}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
AUTOSTART="$HOME/.config/autostart/caparazon.desktop"

# La ruta de la shell es la del arranque automático real del usuario.
SHELL_PATH="$(sed -n 's/.*quickshell -p \([^ ]*\).*/\1/p' "$AUTOSTART" 2>/dev/null | head -n 1)"
# Arranque con el lanzador (aplica la escala): sale la ruta del script.
if [ -z "$SHELL_PATH" ]; then
    SHELL_PATH="$(sed -n 's|^Exec=\(.*\)/scripts/caparazon-shell$|\1|p' "$AUTOSTART" 2>/dev/null | head -n 1)"
fi
if [ -z "$SHELL_PATH" ]; then
    echo "caparazon-guardian: no encuentro la ruta de la shell en $AUTOSTART" >&2
    exit 1
fi

current_log=""
tail_pid=""

while true; do
    pid="$(pgrep -f "quickshell -p $SHELL_PATH" 2>/dev/null | head -n 1 || true)"
    log=""
    if [ -n "$pid" ] && [ -e "$RUNTIME_DIR/quickshell/by-pid/$pid/log.log" ]; then
        log="$RUNTIME_DIR/quickshell/by-pid/$pid/log.log"
    fi

    if [ -n "$log" ] && [ "$log" != "$current_log" ]; then
        if [ -n "$tail_pid" ]; then
            kill "$tail_pid" 2>/dev/null || true
        fi
        current_log="$log"
        tail -F -n 0 -- "$log" 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                *"Graphics device lost"*)
                    systemctl --user restart "$SERVICE" || true
                    # Deja respirar al arranque para no encadenar reinicios.
                    sleep 5
                    ;;
            esac
        done &
        tail_pid=$!
    fi

    sleep 2
done

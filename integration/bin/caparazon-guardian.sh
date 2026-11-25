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

SERVICE="${CAPARAZON_SERVICE:-caparazon-shell.service}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# La ruta de la shell la dice la unit que la arranca.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SELF/caparazon-shell-path.sh"
if [ ! -x "$HELPER" ]; then
    HELPER="$(command -v caparazon-shell-path 2>/dev/null || true)"
fi

# Al inicio de sesión la shell puede tardar en aparecer: el guardián espera
# en vez de rendirse y dejar la sesión sin vigilancia.
wait_for_shell() {
    local deadline=$((SECONDS + 60))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if [ -n "$HELPER" ] && [ -x "$HELPER" ]; then
            SHELL_PATH="$("$HELPER" 2>/dev/null || true)"
        fi
        [ -n "$SHELL_PATH" ] && return 0
        sleep 1
    done
    return 1
}

SHELL_PATH=""
if ! wait_for_shell; then
    echo "caparazon-guardian: no encuentro la ruta de la shell de Caparazon" >&2
    exit 1
fi

current_log=""
tail_pid=""
missing_polls=0
missing_limit=15

while true; do
    pid="$(pgrep -f "quickshell -p $SHELL_PATH" 2>/dev/null | head -n 1 || true)"

    # Arranque fallido (permisos, error de QML, unidad rota): sin shell no
    # hay ni barra ni menús, así que si lleva ~30 s ausente se relanza.
    if [ -n "$pid" ]; then
        missing_polls=0
    elif systemctl --user is-active "$SERVICE" >/dev/null 2>&1; then
        # systemd está levantando la shell: el proceso aún no aparece.
        missing_polls=0
    else
        missing_polls=$((missing_polls + 1))
        if [ "$missing_polls" -ge "$missing_limit" ]; then
            missing_polls=0
            if systemctl --user cat "$SERVICE" >/dev/null 2>&1; then
                # La shell la trae el servicio: se reinicia, no se duplica.
                systemctl --user restart "$SERVICE" 2>/dev/null || true
            else
                setsid sh "$SHELL_PATH/scripts/caparazon-shell" >/dev/null 2>&1 &
            fi
        fi
    fi

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

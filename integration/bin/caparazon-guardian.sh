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
# cuanto aparece la pérdida de contexto. Vive en el arranque automático del
# usuario y no escribe nada en disco.
set -u

SERVICE="${CAPARAZON_SERVICE:-app-caparazon@autostart.service}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOG_DIR="$RUNTIME_DIR/quickshell/by-id"

# La shell tarda en crear su log; el id del directorio depende de su ruta.
for _ in $(seq 1 60); do
    compgen -G "$LOG_DIR/*/log.log" >/dev/null && break
    sleep 2
done

shopt -s nullglob
logs=("$LOG_DIR"/*/log.log)
if [ "${#logs[@]}" -eq 0 ]; then
    echo "caparazon-guardian: no encuentro el log de Quickshell en $LOG_DIR" >&2
    exit 1
fi

tail -F -n 0 -- "${logs[@]}" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        *"Graphics device lost"*)
            systemctl --user restart "$SERVICE" || true
            # Deja respirar al arranque para no encadenar reinicios.
            sleep 5
            ;;
    esac
done

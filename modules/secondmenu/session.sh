#!/usr/bin/env bash
# Salida: "<kind> <epoch>" con kind = session (última sesión activa) o system
# (arranque del equipo). Vacío si no se puede calcular.
sid="${XDG_SESSION_ID:-}"
if [ -n "$sid" ]; then
    for prop in ActiveEnterTimestamp Timestamp; do
        raw="$(loginctl show-session "$sid" -p "$prop" --value 2>/dev/null)"
        if [ -n "$raw" ]; then
            epoch="$(date -d "$raw" +%s 2>/dev/null)"
            if [ -n "$epoch" ]; then
                printf 'session %s\n' "$epoch"
                exit 0
            fi
        fi
    done
fi
epoch="$(date -d "$(uptime -s)" +%s 2>/dev/null)"
[ -n "$epoch" ] && printf 'system %s\n' "$epoch"

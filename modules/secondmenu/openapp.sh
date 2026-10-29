#!/usr/bin/env bash
# Activa la aplicación que emitió una notificación.
#
#   openapp.sh <desktopEntry>
#
# <desktopEntry> es el id D-Bus del .desktop (org.kde.dolphin) o su nombre de
# archivo (dolphin.desktop). Se valida antes de usarlo porque llega desde una
# notificación, es decir, desde fuera: nada de rutas ni metacaracteres.
set -u

entry="${1:-}"
entry="${entry%.desktop}"

if [[ ! "$entry" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "openapp: entrada inválida" >&2
    exit 2
fi

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

# Rutas donde puede vivir el .desktop, del sistema de usuario al del sistema.
for dir in \
    "$data_home/applications" \
    /usr/local/share/applications \
    /usr/share/applications \
    "$data_home/flatpak/exports/share/applications" \
    /var/lib/flatpak/exports/share/applications; do
    if [ -f "$dir/$entry.desktop" ]; then
        # Desacoplado: hay .desktop que son AppImage y se quedan colgados del
        # padre; no queremos que el Process de QML espere por ellos.
        setsid gio launch "$dir/$entry.desktop" >/dev/null 2>&1 </dev/null &
        exit 0
    fi
done

# Sin archivo a la vista: que KDE lo resuelva por su servicio.
if command -v kstart >/dev/null 2>&1; then
    setsid kstart --application "$entry" >/dev/null 2>&1 </dev/null &
    exit 0
fi

echo "openapp: no se encontró $entry.desktop" >&2
exit 1

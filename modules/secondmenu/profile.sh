#!/usr/bin/env bash
# Salida: primera línea = nombre visible; segunda = URL file:// del avatar
# (vacía si no hay ninguno). Uso: bash profile.sh
user="${USER:-$(id -un)}"
name="$(getent passwd "$user" | cut -d: -f5 | cut -d, -f1)"
[ -z "$name" ] && name="$user"
printf '%s\n' "$name"

# 1) AccountsService vía D-Bus (icono real configurado en KDE)
icon="$(busctl --system get-property org.freedesktop.Accounts \
    /org/freedesktop/Accounts/User$(id -u) \
    org.freedesktop.Accounts.User IconFile 2>/dev/null | cut -d' ' -f2- | tr -d '"')"
if [ -n "$icon" ] && [ -f "$icon" ]; then
    printf 'file://%s\n' "$icon"
    exit 0
fi

# 2) Archivo de usuario AccountsService (fallback)
acct="/var/lib/AccountsService/users/$user"
if [ -f "$acct" ]; then
    icon="$(grep -E '^Icon=' "$acct" | cut -d= -f2-)"
    if [ -n "$icon" ] && [ -f "$icon" ]; then
        printf 'file://%s\n' "$icon"
        exit 0
    fi
fi

# 3) Rutas tradicionales
for f in "$HOME/.local/share/faces/$user" "$HOME/.face" "$HOME/.face.icon" "/usr/share/faces/$user"; do
    if [ -f "$f" ]; then
        printf 'file://%s\n' "$f"
        exit 0
    fi
done
printf '\n'

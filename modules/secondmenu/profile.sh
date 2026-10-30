#!/usr/bin/env bash
# Salida: primera línea = nombre visible; segunda = URL file:// del avatar
# (vacía si no hay ninguno). Uso: bash profile.sh
user="${USER:-$(id -un)}"
name="$(getent passwd "$user" | cut -d: -f5 | cut -d, -f1)"
[ -z "$name" ] && name="$user"
printf '%s\n' "$name"

acct="/var/lib/AccountsService/users/$user"
if [ -f "$acct" ]; then
    icon="$(grep -E '^Icon=' "$acct" | cut -d= -f2-)"
    if [ -n "$icon" ] && [ -f "$icon" ]; then
        printf 'file://%s\n' "$icon"
        exit 0
    fi
fi

for f in "$HOME/.local/share/faces/$user" "$HOME/.face" "$HOME/.face.icon" "/usr/share/faces/$user"; do
    if [ -f "$f" ]; then
        printf 'file://%s\n' "$f"
        exit 0
    fi
done
printf '\n'

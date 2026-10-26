#!/usr/bin/env bash
# Arranca el puente de escritorios (demonio + script KWin) si falta.
# Idempotente: se puede correr en cada login sin duplicar nada.
DAEMON="$HOME/.local/bin/ezku-desktops-daemon.py"
SCRIPT="$HOME/.local/share/kwin/scripts/ezkudesktops/contents/code/main.js"

pgrep -f "ezku-desktops-daemon.py" >/dev/null || {
    nohup python3 "$DAEMON" >/tmp/ezku-desktops.log 2>&1 &
    disown
}

for _ in $(seq 1 30); do
    qdbus6 --session org.ezku.Desktops /Desktops org.ezku.Desktops.GetState >/dev/null 2>&1 && break
    sleep 1
done

if ! qdbus6 --session org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded ezkudesktops 2>/dev/null | grep -qi true; then
    qdbus6 --session org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$SCRIPT" ezkudesktops >/dev/null 2>&1
    qdbus6 --session org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1
fi

#!/usr/bin/env bash
# Clima actual con Open-Meteo (sin API key). Imprime el JSON de /forecast y lo
# cachea 15 min. Coordenadas: ~/.config/caparazon/weather.json; si faltan, se
# geolocaliza por IP (ipapi.co) una sola vez.
CFG="$HOME/.config/caparazon/weather.json"
CACHE="$HOME/.cache/caparazon/weather.json"
mkdir -p "$(dirname "$CACHE")"

now=$(date +%s)
if [ -f "$CACHE" ]; then
    mtime=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -lt 900 ]; then
        cat "$CACHE"
        exit 0
    fi
fi

read_json() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2" 2>/dev/null; }

lat=""; lon=""
if [ -f "$CFG" ]; then
    lat="$(read_json "$CFG" latitude)"
    lon="$(read_json "$CFG" longitude)"
fi

if [ -z "$lat" ] || [ -z "$lon" ]; then
    # ipinfo.io devuelve "loc": "lat,lon" y "city". Si falla, se conserva el
    # último config que hubiera.
    loc_json="$(curl -fsS --max-time 6 https://ipinfo.io/json 2>/dev/null || true)"
    if [ -n "$loc_json" ]; then
        read -r lat lon city < <(printf '%s' "$loc_json" | python3 -c '
import json,sys
data = json.load(sys.stdin)
lat, lon = (data.get("loc") or "0,0").split(",")
print(lat, lon, data.get("city") or "")
' 2>/dev/null)
        if [ -n "$lat" ] && [ -n "$lon" ] && [ "$lat" != "0" ]; then
            mkdir -p "$(dirname "$CFG")"
            printf '{"latitude": %s, "longitude": %s, "city": "%s"}\n' \
                "$lat" "$lon" "$city" > "$CFG"
        fi
    fi
fi

[ -z "$lat" ] || [ -z "$lon" ] && exit 1

resp="$(curl -fsS --max-time 8 \
    "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7" \
    2>/dev/null || true)"
[ -z "$resp" ] && exit 1

printf '%s' "$resp" > "$CACHE"
printf '%s' "$resp"

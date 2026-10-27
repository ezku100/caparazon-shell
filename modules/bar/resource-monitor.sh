#!/usr/bin/env bash
# Muestreo ligero de CPU, RAM, GPU, swap/zram, red y perfil de energía.
# Una sola instancia global; entrega una línea por segundo.
set -u

prev_total=
prev_idle=
prev_rx=
prev_tx=
prev_iface=
power_profile=balanced
tick=0

while true; do
    tick=$((tick + 1))

    # CPU agregada desde /proc/stat.
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat || break
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle_total=$((idle + iowait))

    if [[ -n "${prev_total:-}" ]]; then
        delta=$((total - prev_total))
        idle_delta=$((idle_total - prev_idle))
        if (( delta > 0 )); then
            cpu=$((100 * (delta - idle_delta) / delta))
        else
            cpu=0
        fi
    else
        cpu=0
    fi

    prev_total=$total
    prev_idle=$idle_total

    # RAM y swap/zram desde /proc/meminfo sin subshells ni awk.
    mem_total=0
    mem_available=0
    swap_total=0
    swap_free=0
    while IFS=": " read -r key val _; do
        case "$key" in
            MemTotal) mem_total=$val ;;
            MemAvailable) mem_available=$val ;;
            SwapTotal) swap_total=$val ;;
            SwapFree) swap_free=$val ;;
        esac
    done < /proc/meminfo

    if (( mem_total > 0 )); then
        ram=$((100 * (mem_total - mem_available) / mem_total))
    else
        ram=0
    fi

    if (( swap_total > 0 )); then
        swap=$((100 * (swap_total - swap_free) / swap_total))
    else
        swap=0
    fi

    # GPU AMD (amdgpu). Si no hay dato, queda en 0.
    gpu=0
    for f in /sys/class/drm/card*/device/gpu_busy_percent; do
        if [[ -r "$f" ]]; then
            gpu=$(<"$f")
            break
        fi
    done

    # Red: interfaz por defecto en cache (evita llamar a ip/awk cada segundo).
    if [[ -z "${iface:-}" || ! -d "/sys/class/net/$iface" ]]; then
        iface=""
        if [[ -r /proc/net/route ]]; then
            while read -r ifn dest _; do
                if [[ "$dest" == "00000000" ]]; then
                    iface="$ifn"
                    break
                fi
            done < /proc/net/route
        fi
        if [[ -z "$iface" ]]; then
            for d in /sys/class/net/*; do
                bn="${d##*/}"
                if [[ "$bn" != "lo" && "$bn" != "*" ]]; then
                    iface="$bn"
                    break
                fi
            done
        fi

        speed=1000
        if [[ -n "${iface:-}" && -r "/sys/class/net/$iface/speed" ]]; then
            read -r speed < "/sys/class/net/$iface/speed" 2>/dev/null || speed=1000
            if ! [[ "$speed" =~ ^[0-9]+$ ]] || (( speed <= 0 )); then
                speed=1000
            fi
        fi
    fi

    net=0
    if [[ -n "${iface:-}" ]]; then
        rx=0
        tx=0
        [[ -r "/sys/class/net/$iface/statistics/rx_bytes" ]] && read -r rx < "/sys/class/net/$iface/statistics/rx_bytes"
        [[ -r "/sys/class/net/$iface/statistics/tx_bytes" ]] && read -r tx < "/sys/class/net/$iface/statistics/tx_bytes"

        if [[ "$iface" == "${prev_iface:-}" && -n "${prev_rx:-}" && -n "${prev_tx:-}" ]]; then
            bytes=$(( (rx - prev_rx) + (tx - prev_tx) ))
            if (( bytes < 0 )); then
                bytes=0
            fi

            net=$(( bytes * 8 * 100 / (speed * 1000000) ))
            if (( net > 100 )); then
                net=100
            fi
        fi

        prev_iface=$iface
        prev_rx=$rx
        prev_tx=$tx
    fi

    # Perfil de energía de PowerDevil; se consulta cada 6 s para ahorrar CPU/DBus.
    if (( tick % 6 == 1 )); then
        profile=$(qdbus6 org.kde.Solid.PowerManagement \
            /org/kde/Solid/PowerManagement/Actions/PowerProfile \
            org.kde.Solid.PowerManagement.Actions.PowerProfile.currentProfile 2>/dev/null || true)
        case "$profile" in
            performance|balanced|power-saver) power_profile=$profile ;;
        esac
    fi

    printf '%s %s %s %s %s %s\n' \
        "$cpu" "$ram" "$gpu" "$swap" "$net" "$power_profile"
    sleep 1
done

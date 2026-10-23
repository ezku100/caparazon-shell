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

    # RAM y swap/zram desde /proc/meminfo.
    read -r mem_total mem_available swap_total swap_free < <(
        awk '
            /^MemTotal:/{t=$2}
            /^MemAvailable:/{a=$2}
            /^SwapTotal:/{st=$2}
            /^SwapFree:/{sf=$2}
            END{print t, a, st, sf}
        ' /proc/meminfo
    )

    if [[ -n "${mem_total:-}" && -n "${mem_available:-}" && "$mem_total" -gt 0 ]]; then
        ram=$((100 * (mem_total - mem_available) / mem_total))
    else
        ram=0
    fi

    if [[ -n "${swap_total:-}" && -n "${swap_free:-}" && "$swap_total" -gt 0 ]]; then
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

    # Red: interfaz por defecto + velocidad del enlace.
    iface=$(ip route show default 2>/dev/null | awk '
        NR == 1 {
            for (i = 1; i <= NF; ++i)
                if ($i == "dev") { print $(i + 1); exit }
        }
    ')

    if [[ -z "${iface:-}" ]]; then
        iface=$(ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -1)
    fi

    net_icon=network-wired
    if [[ -n "${iface:-}" && -d "/sys/class/net/$iface/wireless" ]]; then
        net_icon=network-wireless
    fi

    net=0
    if [[ -n "${iface:-}" ]]; then
        rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)

        if [[ "$iface" == "${prev_iface:-}" && -n "${prev_rx:-}" && -n "${prev_tx:-}" ]]; then
            bytes=$(( (rx - prev_rx) + (tx - prev_tx) ))
            if (( bytes < 0 )); then
                bytes=0
            fi

            speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || echo 0)
            if ! [[ "$speed" =~ ^[0-9]+$ ]] || (( speed <= 0 )); then
                speed=1000
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

    # Perfil de energía de PowerDevil; se consulta cada 2 s.
    if (( tick % 2 == 1 )); then
        profile=$(qdbus6 org.kde.Solid.PowerManagement \
            /org/kde/Solid/PowerManagement/Actions/PowerProfile \
            org.kde.Solid.PowerManagement.Actions.PowerProfile.currentProfile 2>/dev/null || true)
        case "$profile" in
            performance|balanced|power-saver) power_profile=$profile ;;
        esac
    fi

    printf '%s %s %s %s %s %s %s\n' \
        "$cpu" "$ram" "$gpu" "$swap" "$net" "$power_profile" "$net_icon"
    sleep 1
done

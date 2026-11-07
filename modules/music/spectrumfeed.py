#!/usr/bin/env python3
"""Sampler de espectro para el modo compacto de Música.

Es una adaptación del ``wavefeed.py`` del plugin de Noctalia: lee el FIFO raw
de cava en bucle y escribe ``waves.json`` con los 32 niveles del frame, para
que el panel los pinte sin tener que hablar con cava.

Se llama ``spectrumfeed.py`` y no ``wavefeed.py`` a propósito: el sampler del
plugin de Noctalia se detiene con ``pkill -f wavefeed[.]py`` y este con
``pkill -f spectrumfeed[.]py``, así los dos pueden convivir.

Uso: spectrumfeed.py <datadir>
"""

import json
import os
import subprocess
import sys
import time

BARS = 32
RATE = 30
# cava mide la salida real, así que con el volumen bajo el espectro se encoge.
# Se normaliza contra un pico de referencia que se mueve despacio en los dos
# sentidos (12 % por frame): el nivel se ve lleno a cualquier volumen sin
# amplificar el silencio ni dar tirones cuando entra un golpe fuerte.
NOISE_FLOOR = 6
REFERENCE_RATE = 0.12
# Cada cuánto se comprueba que cava sigue vivo si el FIFO no da datos.
CHECK_SECONDS = 2.0
IDLE_SLEEP = 0.02


def normalize(frame, reference):
    """Escala el frame para que su banda más fuerte llegue arriba.

    Devuelve ``(frame_escalado, referencia_nueva)``. Si el frame entero está
    por debajo del suelo de ruido es silencio: barras a cero y referencia
    reiniciada, para que al volver el sonido el nivel se recupere al momento.
    """
    peak = max(frame, default=0)
    if peak < NOISE_FLOOR:
        return [0] * len(frame), 0.0
    if reference <= 0.0:
        reference = float(peak)
    else:
        reference += (peak - reference) * REFERENCE_RATE
    scale = 255.0 / reference
    return [min(255, int(round(value * scale))) for value in frame], reference


def paths(datadir):
    """Devuelve (config, fifo, waves) dentro del datadir."""
    return (os.path.join(datadir, "cava.conf"),
            os.path.join(datadir, "cava.fifo"),
            os.path.join(datadir, "waves.json"))


def running(pattern):
    """PIDs que están corriendo con ese patrón, sin contarse a sí mismo."""
    try:
        out = subprocess.run(["pgrep", "-f", pattern],
                             capture_output=True, text=True,
                             timeout=5).stdout
    except Exception:
        return []
    me = os.getpid()
    found = []
    for line in out.splitlines():
        try:
            pid = int(line.strip())
        except ValueError:
            continue
        if pid != me:
            found.append(pid)
    return found


def cava_config(fifo):
    """La configuración de cava que usa el sampler."""
    return (f"[general]\nframerate = {RATE}\nbars = 32\n"
            "autosens = 1\nsensitivity = 100\nsleep_timer = 3\n"
            "[output]\nmethod = raw\nchannels = mono\n"
            "mono_option = average\n"
            f"raw_target = {fifo}\n"
            "data_format = binary\nbit_format = 8bit\n")


def ensure_cava(conf, fifo):
    """Arranca cava si no está ya corriendo con esta configuración."""
    if running(f"cava -p {conf}"):
        return
    os.makedirs(os.path.dirname(conf), exist_ok=True)
    with open(conf, "w") as f:
        f.write(cava_config(fifo))
    if not os.path.exists(fifo):
        os.mkfifo(fifo)
    subprocess.Popen(["cava", "-p", conf],
                     start_new_session=True,
                     stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)


def split_frames(buffer, size=BARS):
    """Separa los frames completos del buffer y devuelve ``(frames, resto)``.

    La lectura es no bloqueante: puede devolver medio frame. El resto se
    guarda para el siguiente ciclo en vez de perderse.
    """
    frames = []
    while len(buffer) >= size:
        frames.append(buffer[:size])
        buffer = buffer[size:]
    return frames, buffer


def read_chunk(fd):
    """Lee lo que haya en el FIFO; ``None`` si está vacío o sin escritores."""
    try:
        return os.read(fd, 4096)
    except BlockingIOError:
        return None


def publish(waves, spec):
    """Publica un frame de forma atómica para que la shell nunca lea medio."""
    try:
        with open(waves + ".tmp", "w") as f:
            json.dump({"ts": time.time(), "spec": spec}, f)
        os.replace(waves + ".tmp", waves)
    except OSError:
        pass


def main(datadir):
    """Publica los frames de cava en waves.json hasta que la maten."""
    conf, fifo, waves = paths(datadir)
    os.makedirs(datadir, exist_ok=True)
    if running(f"spectrumfeed.py {datadir}"):
        return
    if os.fork() != 0:
        time.sleep(0.5)
        os._exit(0)
    if os.fork() != 0:
        os._exit(0)
    os.setsid()
    ensure_cava(conf, fifo)
    fd = os.open(fifo, os.O_RDONLY | os.O_NONBLOCK)
    buffer = b""
    reference = 0.0
    last_check = 0.0
    try:
        while True:
            chunk = read_chunk(fd)
            if chunk:
                buffer += chunk
                frames, buffer = split_frames(buffer)
                for frame in frames:
                    spec, reference = normalize(frame, reference)
                    publish(waves, spec)
                continue
            now = time.monotonic()
            if now - last_check >= CHECK_SECONDS:
                last_check = now
                if not running(f"cava -p {conf}"):
                    ensure_cava(conf, fifo)
            time.sleep(IDLE_SLEEP)
    finally:
        os.close(fd)


if __name__ == "__main__":
    main(sys.argv[1])

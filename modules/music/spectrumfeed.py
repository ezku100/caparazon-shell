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
RATE = 12


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
    return ("[general]\nframerate = 10\nbars = 32\n"
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
    fd = os.open(fifo, os.O_RDONLY)
    try:
        buf = b""
        period = 1.0 / RATE
        nxt = time.time()
        while True:
            chunk = os.read(fd, 4096)
            if not chunk:
                time.sleep(0.05)
                continue
            buf += chunk
            if len(buf) >= BARS and time.time() >= nxt:
                frame = buf[-BARS:]
                buf = b""
                nxt = time.time() + period
                try:
                    with open(waves + ".tmp", "w") as f:
                        json.dump({"ts": time.time(),
                                   "spec": list(frame)}, f)
                    os.replace(waves + ".tmp", waves)
                except OSError:
                    pass
    finally:
        os.close(fd)


if __name__ == "__main__":
    main(sys.argv[1])

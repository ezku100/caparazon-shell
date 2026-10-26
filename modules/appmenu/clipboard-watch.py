#!/usr/bin/env python3
"""Guarda el portapapeles de Wayland en un historial JSON pequeño.

wl-paste --watch ejecuta este script con el contenido actual en stdin cada
vez que cambia el portapapeles. El archivo se escribe de forma atómica y con
bloqueo para no perder entradas si llegan dos cambios seguidos.
"""

import fcntl
import json
import os
import sys
import tempfile
import time

MAX_ITEMS = 40
MAX_CHARS = 100000


def history_path():
    cache = os.environ.get("XDG_CACHE_HOME")
    if not cache:
        cache = os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(cache, "caparazon", "clipboard-history.json")


def load(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        items = data.get("items", [])
        return items if isinstance(items, list) else []
    except (OSError, ValueError):
        return []


def save(path, items):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".clipboard-", suffix=".json", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump({"items": items}, handle, ensure_ascii=False,
                      separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def main():
    raw = sys.stdin.buffer.read()
    if not raw or b"\x00" in raw:
        return

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return

    if not text.strip():
        return
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS]

    path = history_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lock_path = path + ".lock"

    with open(lock_path, "a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        items = [
            item for item in load(path)
            if isinstance(item, dict) and item.get("text") != text
        ]
        items.insert(0, {"text": text, "ts": time.time()})
        save(path, items[:MAX_ITEMS])


if __name__ == "__main__":
    main()

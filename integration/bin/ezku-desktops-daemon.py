#!/usr/bin/env python3
"""Puente escritorios KDE -> plugin pacman de Noctalia.

Guarda el estado (actual, lista, ocupados) que le empuja el script KWin
y lo sirve en formato líneas por D-Bus. Sin esta pieza el widget solo
puede leer actual+lista por VDM, pero no qué escritorios tienen ventanas.
"""
import json
import os
import sys

import gi
gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib

BUS = "org.ezku.Desktops"
PATH = "/Desktops"
IFACE = "org.ezku.Desktops"
CACHE = os.path.expanduser("~/.cache/ezku-desktops.json")

INTROSPECT = f"""<node>
  <interface name="{IFACE}">
    <method name="PushState"><arg name="json" type="s" direction="in"/></method>
    <method name="GetState"><arg name="state" type="s" direction="out"/></method>
  </interface>
</node>"""

state = {"current": None, "desktops": [], "active": {}, "windows": [], "perOutput": {}, "focusedScreen": "", "occupiedPerOutput": {}}


def save():
    try:
        tmp = CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, CACHE)
    except OSError:
        pass


def load():
    try:
        with open(CACHE) as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("desktops"), list):
            state.update(data)
    except (OSError, ValueError):
        pass


ASSETS = os.path.expanduser("~/.local/share/noctalia/plugins/pacman-desktops/assets")

_app_names = {}


def app_name(wmclass):
    key = (wmclass or "").lower()
    if not key:
        return ""
    if key in _app_names:
        return _app_names[key]
    name = ""
    try:
        apps = Gio.app_info_get_all()
        for app in apps:
            try:
                wm = (app.get_startup_wm_class() or "").lower()
            except Exception:
                wm = ""
            if wm and wm == key:
                name = app.get_display_name() or ""
                break
        if not name:
            for app in apps:
                try:
                    aid = (app.get_id() or "").lower().replace(".desktop", "")
                except Exception:
                    aid = ""
                if aid and (aid == key or aid.split(".")[-1] == key):
                    name = app.get_display_name() or ""
                    break
        if not name:
            for app in apps:
                try:
                    wm = (app.get_startup_wm_class() or "").lower()
                    aid = (app.get_id() or "").lower().replace(".desktop", "")
                except Exception:
                    wm, aid = "", ""
                if (wm and (key in wm or wm in key)) or (aid and (key in aid or aid in key)):
                    name = app.get_display_name() or ""
                    break
    except Exception:
        name = ""
    if not name:
        name = key[:1].upper() + key[1:]
    elif name == name.lower() and " " not in name:
        name = name[:1].upper() + name[1:]
    _app_names[key] = name
    return name


def assets_version():
    best = 0
    try:
        for name in os.listdir(ASSETS):
            if name.startswith("v") and name[1:].isdigit():
                best = max(best, int(name[1:]))
    except OSError:
        pass
    return best


def fmt():
    lines = ["current=" + (state["current"] or ""),
             f"assets_v={assets_version()}"]
    act = state.get("active") or {}
    if isinstance(act, dict):
        lines.append("active_caption=" + str(act.get("caption") or ""))
        lines.append("active_class=" + str(act.get("class") or ""))
        lines.append("active_uuid=" + str(act.get("uuid") or ""))
        lines.append("active_name=" + str(act.get("name") or ""))
    for d in state["desktops"]:
        occ = 1 if d.get("id") in set(state.get("occupied") or []) else 0
        lines.append(f"{d.get('pos', 0)}\t{d.get('id', '')}\t{d.get('name', '')}\t{occ}")
    return "\n".join(lines)


def on_method(conn, sender, path, iface, method, params, invocation):
    if method == "PushState":
        try:
            data = json.loads(params[0])
        except ValueError:
            invocation.return_value(None)
            return
        if isinstance(data, dict):
            if isinstance(data.get("desktops"), list):
                state["desktops"] = data["desktops"][:24]
            if "current" in data:
                state["current"] = data["current"]
            if isinstance(data.get("occupied"), list):
                state["occupied"] = data["occupied"][:24]
            if isinstance(data.get("windows"), list):
                state["windows"] = data["windows"][:64]
            if isinstance(data.get("active"), dict):
                cls = str(data["active"].get("class") or "")[:128]
                state["active"] = {
                    "caption": str(data["active"].get("caption") or "")[:256],
                    "class": cls,
                    "uuid": str(data["active"].get("uuid") or "")[:64],
                    "name": app_name(cls)[:128],
                }
            if isinstance(data.get("perOutput"), dict):
                state["perOutput"] = {
                    str(k): str(v) for k, v in data["perOutput"].items()
                    if isinstance(k, str) and isinstance(v, str)
                }
            if "focusedScreen" in data:
                state["focusedScreen"] = str(data["focusedScreen"] or "")[:128]
            if isinstance(data.get("occupiedPerOutput"), dict):
                state["occupiedPerOutput"] = {
                    str(k): [str(x) for x in v if isinstance(x, str)][:24]
                    for k, v in data["occupiedPerOutput"].items()
                    if isinstance(k, str) and isinstance(v, list)
                }
            save()
        invocation.return_value(None)
    elif method == "GetState":
        invocation.return_value(GLib.Variant("(s)", (fmt(),)))
    else:
        invocation.return_error_literal(
            Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD,
            f"método desconocido: {method}")


def main():
    load()
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECT)
    loop = GLib.MainLoop()
    Gio.bus_own_name(Gio.BusType.SESSION, BUS, Gio.BusNameOwnerFlags.NONE,
                     None, None, None)
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    conn.register_object(PATH, node.interfaces[0], on_method, None, None)
    print(f"{BUS} listo.", flush=True)
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

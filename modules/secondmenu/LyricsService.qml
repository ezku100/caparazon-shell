import Quickshell
import Quickshell.Io
import QtQuick

/*
  Letras desde LRCLIB (mismo endpoint que usa el plugin de Noctalia) con una
  mejora opcional a tiempos por palabra vía lrcmux.

  El script imprime una línea JSON por resultado:
    1) lo de LRCLIB, en cuanto llega (la letra aparece rápido);
    2) si lrcmux trae marcas <mm:ss.xx> por palabra, esa línea la reemplaza.
  Lo mejor se guarda en ~/.cache/caparazon/lyrics/ para no volver a pedirlo.
*/
Item {
    id: root

    property string lyrics: ""        // sincronizada (LRC), si existe
    property string plainLyrics: ""   // texto plano
    property string status: "idle"    // idle | loading | ok | empty | error

    property var pending: null

    function fetchFor(artist, title, album, duration) {
        root.lyrics = "";
        root.plainLyrics = "";

        if (!artist || !title) {
            root.pending = null;
            root.status = "idle";
            return;
        }

        const args = [artist, title, album || "", String(Math.round(duration || 0))];
        if (proc.running) {
            root.pending = args;
            return;
        }
        root.start(args);
    }

    function start(args) {
        root.status = "loading";
        proc.command = ["bash", "-c", root.script, "lyrics"].concat(args);
        proc.running = true;
    }

    // $1 artista · $2 título · $3 álbum · $4 duración (s)
    readonly property string script: [
        'set -o pipefail',
        'UA="Caparazon (quickshell)"',
        'dir="$HOME/.cache/caparazon/lyrics"; mkdir -p "$dir"',
        'key="$(printf "%s|%s" "$1" "$2" | sha1sum | cut -d" " -f1)"',
        'f="$dir/$key.json"',
        '[ -s "$f" ] && { cat "$f"; echo; exit 0; }',
        'get() { curl -fsS --max-time 8 -A "$UA" -G "$@" | tr -d "\\n\\r"; }',
        // 1) LRCLIB, como el plugin: artista + título + álbum (+ duración)
        'base="$(get https://lrclib.net/api/get --data-urlencode "artist_name=$1" --data-urlencode "track_name=$2" --data-urlencode "album_name=$3" --data-urlencode "duration=$4" 2>/dev/null \\',
        '  || get https://lrclib.net/api/get --data-urlencode "artist_name=$1" --data-urlencode "track_name=$2" --data-urlencode "album_name=$3" 2>/dev/null \\',
        '  || get https://lrclib.net/api/search --data-urlencode "q=$1 $2" 2>/dev/null)"',
        '[ "$base" = "[]" ] && base=""',
        'best="$base"',
        '[ -n "$base" ] && printf "%s\\n" "$base"',
        // 2) mejora a palabra por palabra (si lrcmux la tiene)
        'w="$(get https://lrcmux.dev/api/get --data-urlencode "artist_name=$1" --data-urlencode "track_name=$2" --data-urlencode "album_name=$3" --data-urlencode "duration=$4" --data-urlencode "level=word" 2>/dev/null)" || w=""',
        'if printf "%s" "$w" | grep -Eq "(<|.u003[cC])[0-9]+:[0-9]+"; then best="$w"; printf "%s\\n" "$w"',
        'elif [ -z "$base" ] && [ -n "$w" ] && [ "$w" != "[]" ]; then best="$w"; printf "%s\\n" "$w"; fi',
        '[ -n "$best" ] || exit 1',
        'printf "%s" "$best" > "$f"'
    ].join("\n")

    function pick(obj) {
        // /get devuelve un objeto; /search devuelve una lista.
        if (Array.isArray(obj)) {
            for (let i = 0; i < obj.length; ++i) {
                if (obj[i] && (obj[i].plainLyrics || obj[i].syncedLyrics))
                    return obj[i];
            }
            return null;
        }
        return obj;
    }

    Process {
        id: proc

        // Una línea JSON por resultado; la última (la mejor) manda.
        stdout: SplitParser {
            onRead: data => {
                if (root.pending) return;   // respuesta vieja
                const raw = String(data || "").trim();
                if (!raw) return;
                try {
                    const hit = root.pick(JSON.parse(raw));
                    const synced = hit && hit.syncedLyrics ? hit.syncedLyrics : "";
                    const plain = hit && hit.plainLyrics ? hit.plainLyrics : "";
                    if (!synced && !plain) return;
                    root.lyrics = synced;
                    root.plainLyrics = plain;
                    root.status = "ok";
                    if (synced)
                        console.log("[lyrics]", /<\d+:\d+(?:[.:]\d+)?>/.test(synced)
                            ? "con tiempos por palabra"
                            : "solo tiempos por línea");
                } catch (e) {
                    console.warn("[lyrics] JSON inválido:", e);
                    root.status = "error";
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: if (text) console.warn("[lyrics]", String(text).trim())
        }

        onExited: {
            if (root.status === "loading")
                root.status = "empty";
            if (root.pending) {
                const p = root.pending;
                root.pending = null;
                root.start(p);
            }
        }
    }
}

#!/usr/bin/env python3
import sys, json, urllib.request, urllib.parse

def fetch_lrclib(artist, title):
    try:
        q = urllib.parse.urlencode({"track_name": title, "artist_name": artist})
        url = f"https://lrclib.net/api/get?{q}"
        with urllib.request.urlopen(url, timeout=5) as r:
            data = json.load(r)
        if isinstance(data, list) and data:
            return data[0]
    except Exception:
        pass
    return None

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(json.dumps({"lyrics": ""}))
        sys.exit(0)
    artist = sys.argv[1]
    title = sys.argv[2]
    res = fetch_lrclib(artist, title)
    if res and res.get("syncedLyrics"):
        out = {"lyrics": res["syncedLyrics"], "plain": res.get("plainLyrics","")}
    else:
        out = {"lyrics": res.get("plainLyrics","") if res else "", "plain": ""}
    print(json.dumps(out))

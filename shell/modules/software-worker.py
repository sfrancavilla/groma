#!/usr/bin/env python3
"""What the Software window knows about packages.

One JSON request per line in, one JSON answer per line out, carrying the
request's id - the same shape as files-worker.py. Each request runs on a
thread of its own, because a search waits on the network and the window
must not wait on it.

Official repositories come from pacman itself: -Sl for what exists, -Qq for
what is installed, -Si/-Qi for details. The AUR comes from its own API, RPC
v5, which carries votes, popularity, maintainer, last update and the
out-of-date flag. Updates come from checkupdates (pacman-contrib), which
reads a copy of the sync database and so never leaves the real one half
synced; AUR updates are the installed foreign packages whose AUR version
is newer, by vercmp.

Nothing here installs anything. Installing needs a password and prints a
lot, so the window opens a terminal for it.
"""
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

AUR = "https://aur.archlinux.org/rpc/v5"
lock = threading.Lock()


def emit(**obj):
    with lock:
        print(json.dumps(obj), flush=True)


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def aur(path, **params):
    query = urllib.parse.urlencode(params, doseq=True)
    url = f"{AUR}/{path}" + (f"?{query}" if query else "")
    req = urllib.request.Request(url, headers={"User-Agent": "groma-software"})
    with urllib.request.urlopen(req, timeout=10) as reply:
        return json.load(reply).get("results", [])


def aur_row(r):
    return {
        "name": r.get("Name"), "version": r.get("Version"), "desc": r.get("Description") or "",
        "votes": r.get("NumVotes", 0), "popularity": round(r.get("Popularity", 0), 2),
        "maintainer": r.get("Maintainer") or "orphaned", "outOfDate": r.get("OutOfDate") is not None,
        "modified": r.get("LastModified", 0), "source": "aur",
    }


def installed_sets():
    native = set(run("pacman", "-Qqn").split())
    foreign = {}
    for line in run("pacman", "-Qm").splitlines():
        parts = line.split()
        if len(parts) == 2:
            foreign[parts[0]] = parts[1]
    return native, foreign


# --- operations -------------------------------------------------------------

def op_state(_):
    """What exists in the repositories and what is installed."""
    repos = {}
    for line in run("pacman", "-Sl").splitlines():
        parts = line.split()
        if len(parts) >= 3:
            repos[parts[1]] = {"repo": parts[0], "version": parts[2]}
    native, foreign = installed_sets()
    synced = 0
    try:
        synced = max(os.path.getmtime(os.path.join("/var/lib/pacman/sync", f))
                     for f in os.listdir("/var/lib/pacman/sync") if f.endswith(".db"))
    except (OSError, ValueError):
        pass
    # What was installed on purpose, not pulled in as a dependency: the
    # Installed page lists these.
    explicit = []
    for line in run("pacman", "-Qe").splitlines():
        parts = line.split()
        if len(parts) == 2:
            explicit.append({"name": parts[0], "version": parts[1],
                             "source": "aur" if parts[0] in foreign else "official"})
    return {"repos": repos, "installed": sorted(native | set(foreign)), "foreign": foreign,
            "explicit": explicit,
            "synced": synced, "helper": next((h for h in ("yay", "paru") if shutil.which(h)), ""),
            "checkupdates": shutil.which("checkupdates") is not None}


def op_search(req):
    term = req["term"].strip()
    native, foreign = installed_sets()
    official = []
    out = run("pacman", "-Ss", "--", term)
    lines = out.splitlines()
    for i in range(0, len(lines) - 1, 2):
        head, desc = lines[i], lines[i + 1].strip()
        repo_name, _, rest = head.partition("/")
        name, version = (rest.split() + ["", ""])[:2]
        official.append({"name": name, "version": version, "desc": desc, "repo": repo_name,
                         "source": "official", "installed": name in native or name in foreign})
    # A name carrying the term is what was asked for; pacman -Ss also
    # matches descriptions, which buries it. Keep the names when there are
    # any, the description matches only when there are none.
    t = term.lower()
    named = [p for p in official if t in p["name"].lower()]
    official = named or official
    official.sort(key=lambda p: (not p["name"].startswith(t), t not in p["name"], p["name"]))
    sizes = {}
    names = [p["name"] for p in official[:12]]
    if names:
        name = None
        for line in run("pacman", "-Si", *names).splitlines():
            if line.startswith("Name"):
                name = line.split(":", 1)[1].strip()
            elif line.startswith("Installed Size") and name:
                sizes[name] = line.split(":", 1)[1].strip()
    for p in official:
        p["size"] = sizes.get(p["name"], "")
    aur_rows, aur_error = [], ""
    try:
        found = aur(f"search/{urllib.parse.quote(term)}", by="name-desc")
        # Names carrying the term first, then by how much the AUR uses them.
        named = [r for r in found if t in (r.get("Name") or "").lower()]
        found = named or found
        found.sort(key=lambda r: (not (r.get("Name") or "").lower().startswith(t), -r.get("Popularity", 0)))
        aur_rows = [dict(aur_row(r), installed=r.get("Name") in foreign) for r in found[:30]]
    except Exception as err:          # offline, or the AUR is down
        aur_error = "The AUR could not be reached"
    return {"term": term, "official": official[:30], "aur": aur_rows, "aurError": aur_error}


def op_info(req):
    name, source = req["name"], req.get("source", "official")
    if source == "aur":
        found = aur("info", **{"arg[]": [name]})
        if not found:
            return {"missing": True}
        r = found[0]
        info = aur_row(r)
        info["depends"] = len(r.get("Depends", []) or [])
        info["makedepends"] = len(r.get("MakeDepends", []) or [])
        info["url"] = f"https://aur.archlinux.org/packages/{name}"
        info["upstream"] = r.get("URL") or ""
        return info
    native, foreign = installed_sets()
    installed = name in native
    text = run("pacman", "-Qi" if installed else "-Si", name)
    fields = {}
    key = None
    for line in text.splitlines():
        if ":" in line and not line.startswith(" "):
            key, _, value = line.partition(":")
            key = key.strip()
            fields[key] = value.strip()
        elif key:
            fields[key] += " " + line.strip()
    deps = fields.get("Depends On", "None")
    repo = fields.get("Repository", "")
    if installed and not repo:
        repo = next((l.split()[0] for l in run("pacman", "-Sl").splitlines() if l.split()[1:2] == [name]), "")
    return {"name": name, "version": fields.get("Version", ""), "desc": fields.get("Description", ""),
            "repo": repo, "source": "official", "installed": installed,
            "size": fields.get("Installed Size", ""), "download": fields.get("Download Size", ""),
            "built": fields.get("Build Date", ""),
            "depends": 0 if deps == "None" else len(deps.split()),
            "url": f"https://archlinux.org/packages/{repo}/x86_64/{name}" if repo else "",
            "upstream": fields.get("URL", "")}


def op_updates(_):
    official = []
    if shutil.which("checkupdates"):
        for line in run("checkupdates").splitlines():
            parts = line.split()
            if len(parts) >= 4:
                official.append({"name": parts[0], "from": parts[1], "to": parts[3], "source": "official"})
    native, foreign = installed_sets()
    aur_rows, aur_error = [], ""
    if foreign:
        try:
            found = {r["Name"]: r for r in aur("info", **{"arg[]": list(foreign)})}
            for name, have in foreign.items():
                r = found.get(name)
                if r and run("vercmp", r["Version"], have).strip() == "1":
                    aur_rows.append({"name": name, "from": have, "to": r["Version"], "source": "aur",
                                     "desc": r.get("Description") or ""})
        except Exception:
            aur_error = "The AUR could not be reached"
    # Descriptions for the official ones, in one pacman call.
    if official:
        desc, name = {}, None
        for line in run("pacman", "-Qi", *[u["name"] for u in official]).splitlines():
            if line.startswith("Name"):
                name = line.split(":", 1)[1].strip()
            elif line.startswith("Description") and name:
                desc[name] = line.split(":", 1)[1].strip()
        for u in official:
            u["desc"] = desc.get(u["name"], "")
    return {"official": official, "aur": aur_rows, "aurError": aur_error,
            "checked": time.time(), "hasCheck": shutil.which("checkupdates") is not None}


# --- icons ------------------------------------------------------------------
#
# An application's icon arrives with the application, so a package that is not
# installed has none - unless the icon theme happens to draw it, which Papirus
# usually does, under the name the package's AppStream entry gives. Arch ships
# that catalogue (archlinux-appstream-data) with an icon name per package, and
# a pre-rendered icon for the ones a theme does not cover. Those are JPEG XL,
# which Qt cannot read, so they are converted to PNG once and kept.

APPSTREAM = "/usr/share/swcatalog"
ICON_CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                          "groma", "store-icons")
_catalog = None
_catalog_lock = threading.Lock()


def catalog():
    """pkgname -> (names to try in the icon theme, cached icon files by size)."""
    global _catalog
    with _catalog_lock:
        if _catalog is not None:
            return _catalog
        import gzip
        import xml.etree.ElementTree as ET
        found = {}
        for repo in ("core", "extra", "multilib"):
            path = os.path.join(APPSTREAM, "xml", f"{repo}.xml.gz")
            if not os.path.exists(path):
                continue
            try:
                root = ET.parse(gzip.open(path)).getroot()
            except Exception:
                continue
            origin = root.get("origin") or f"archlinux-arch-{repo}"
            for c in root.iter("component"):
                pkg = c.findtext("pkgname")
                if not pkg:
                    continue
                names, files = [], {}
                for icon in c.findall("icon"):
                    kind, text = icon.get("type"), (icon.text or "").strip()
                    if kind == "stock" and text:
                        names.append(text)
                    elif kind == "cached" and text:
                        size = icon.get("width") or "64"
                        files[size] = os.path.join(APPSTREAM, "icons", origin, f"{size}x{size}", text)
                cid = (c.findtext("id") or "").removesuffix(".desktop")
                if cid:
                    names.append(cid)
                if pkg not in found:
                    found[pkg] = (names, files)
        _catalog = found
        return found


def plain_name(pkg):
    """visual-studio-code-bin -> visual-studio-code, zen-browser-bin -> zen-browser."""
    for suffix in ("-bin", "-git", "-beta", "-nightly", "-appimage"):
        if pkg.endswith(suffix):
            return pkg[: -len(suffix)]
    return pkg


def cached_png(files):
    """The largest cached icon, as a PNG the shell can show; "" if none."""
    for size in ("128", "64", "48"):
        src = files.get(size)
        if not src or not os.path.exists(src):
            continue
        os.makedirs(ICON_CACHE, exist_ok=True)
        out = os.path.join(ICON_CACHE, os.path.basename(src).rsplit(".", 1)[0] + ".png")
        if os.path.exists(out):
            return out
        if src.endswith(".png"):
            return src
        if shutil.which("djxl") and subprocess.run(["djxl", src, out], capture_output=True).returncode == 0:
            return out
    return ""


def op_icons(req):
    cat = catalog()
    result = {}
    for pkg in req.get("packages", []):
        names, files = cat.get(pkg, ([], {}))
        tries = []
        for n in names + [pkg, plain_name(pkg)]:
            if n and n not in tries:
                tries.append(n)
        result[pkg] = {"names": tries, "file": cached_png(files)}
    return {"icons": result}


OPS = {"state": op_state, "search": op_search, "info": op_info, "updates": op_updates, "icons": op_icons}


def handle(request):
    rid = request.get("id")
    op = OPS.get(request.get("op"))
    if op is None:
        emit(id=rid, ok=False, error="Unknown operation")
        return
    try:
        emit(id=rid, ok=True, op=request.get("op"), **op(request))
    except Exception as err:
        emit(id=rid, ok=False, error=str(err))


def main():
    threads = []
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except ValueError:
            continue
        thread = threading.Thread(target=handle, args=(request,), daemon=True)
        thread.start()
        threads.append(thread)
    # Input closed: answer what was asked before going.
    for thread in threads:
        thread.join(timeout=30)


if __name__ == "__main__":
    main()

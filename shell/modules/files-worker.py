#!/usr/bin/env python3
"""The hands of the Files window.

QML can read a folder but not write one, so FilesWindow.qml keeps this
process alive and sends it one JSON request per line; it answers one JSON
line per request, carrying the request's id. Nothing here is asked twice
about the same thing: a conflict or a failure is reported, and the window
decides what to say.

Trash follows the freedesktop spec: a moved file under Trash/files and a
small info file beside it under Trash/info recording where it came from and
when. That is what makes Restore possible, and what lets other file managers
see the same Trash.

A journal of the last few operations gives Undo: a rename undoes as the
reverse rename, a new folder as its removal if still empty, a trash as a
restore, a restore as a trash.
"""
import datetime
import json
import os
import shutil
import sys
import urllib.parse

HOME = os.path.expanduser("~")
TRASH = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"), "Trash")
TRASH_FILES = os.path.join(TRASH, "files")
TRASH_INFO = os.path.join(TRASH, "info")

journal = []


def emit(**obj):
    print(json.dumps(obj), flush=True)


class Refused(Exception):
    """An operation that will not be done, with the sentence that says why."""


def unique(folder, name):
    """`name` if nothing in `folder` has it, else `name 2`, `name 3`, ... with
    the extension kept on the end."""
    if not os.path.lexists(os.path.join(folder, name)):
        return name
    stem, ext = os.path.splitext(name)
    if os.path.isdir(os.path.join(folder, name)) or name.startswith("."):
        stem, ext = name, ""
    n = 2
    while os.path.lexists(os.path.join(folder, f"{stem} {n}{ext}")):
        n += 1
    return f"{stem} {n}{ext}"


def move(src, dst):
    """A rename where possible, a copy-and-delete across devices."""
    try:
        os.rename(src, dst)
    except OSError as err:
        if err.errno == 18:  # EXDEV
            shutil.move(src, dst)
        else:
            raise


def check_name(name):
    if name in ("", ".", "..") or "/" in name:
        raise Refused("That is not a name a file can have")


# --- operations ------------------------------------------------------------

def op_rename(path, name):
    check_name(name)
    folder = os.path.dirname(path)
    target = os.path.join(folder, name)
    if target == path:
        return {"path": path}
    if os.path.lexists(target):
        raise Refused(f"There is already something called {name} here")
    os.rename(path, target)
    journal.append(("rename", target, path))
    return {"path": target}


def op_mkdir(parent, name):
    check_name(name)
    name = unique(parent, name)
    path = os.path.join(parent, name)
    os.mkdir(path)
    journal.append(("mkdir", path))
    return {"path": path}


def trash_one(path):
    os.makedirs(TRASH_FILES, exist_ok=True)
    os.makedirs(TRASH_INFO, exist_ok=True)
    name = unique(TRASH_FILES, os.path.basename(path))
    # The info file first, and exclusively: the spec's way of claiming the
    # name before anything else can.
    while True:
        try:
            fd = os.open(os.path.join(TRASH_INFO, name + ".trashinfo"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            break
        except FileExistsError:
            name = unique(TRASH_FILES, name + " 2")
    with os.fdopen(fd, "w") as info:
        info.write("[Trash Info]\n")
        info.write("Path=" + urllib.parse.quote(path) + "\n")
        info.write("DeletionDate=" + datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S") + "\n")
    try:
        move(path, os.path.join(TRASH_FILES, name))
    except Exception:
        os.unlink(os.path.join(TRASH_INFO, name + ".trashinfo"))
        raise
    return name


def read_info(name):
    origin, deleted = "", ""
    try:
        with open(os.path.join(TRASH_INFO, name + ".trashinfo")) as info:
            for line in info:
                if line.startswith("Path="):
                    origin = urllib.parse.unquote(line[5:].strip())
                elif line.startswith("DeletionDate="):
                    deleted = line[13:].strip()
    except FileNotFoundError:
        pass
    return origin, deleted


def restore_one(name):
    origin, _ = read_info(name)
    if origin == "":
        raise Refused(f"{name} has no record of where it came from")
    parent = os.path.dirname(origin)
    if not os.path.isdir(parent):
        raise Refused(f"The folder {name} came from no longer exists")
    target = os.path.join(parent, unique(parent, os.path.basename(origin)))
    move(os.path.join(TRASH_FILES, name), target)
    try:
        os.unlink(os.path.join(TRASH_INFO, name + ".trashinfo"))
    except FileNotFoundError:
        pass
    return target


def op_trash(paths):
    names = [trash_one(p) for p in paths]
    journal.append(("trash", names))
    return {"count": len(names)}


def op_restore(names):
    restored = [restore_one(n) for n in names]
    journal.append(("restore", restored))
    return {"paths": restored}


def remove(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def op_delete(paths):
    for p in paths:
        remove(p)
        if os.path.dirname(p) == TRASH_FILES:
            try:
                os.unlink(os.path.join(TRASH_INFO, os.path.basename(p) + ".trashinfo"))
            except FileNotFoundError:
                pass
    return {"count": len(paths)}


def op_empty():
    count = 0
    for folder in (TRASH_FILES, TRASH_INFO):
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            remove(os.path.join(folder, name))
            count += folder == TRASH_FILES
    journal.clear()
    return {"count": count}


def op_trashlist():
    items = []
    if os.path.isdir(TRASH_FILES):
        for name in os.listdir(TRASH_FILES):
            origin, deleted = read_info(name)
            items.append({"name": name, "origin": origin, "deleted": deleted})
    return {"items": items}


def op_undo():
    if not journal:
        raise Refused("Nothing to undo")
    entry = journal.pop()
    kind = entry[0]
    if kind == "rename":
        _, now, before = entry
        if os.path.lexists(before):
            raise Refused(f"Cannot undo: {os.path.basename(before)} exists again")
        os.rename(now, before)
        return {"undid": "rename", "path": before}
    if kind == "mkdir":
        path = entry[1]
        if os.listdir(path):
            raise Refused("Cannot undo: the folder is no longer empty")
        os.rmdir(path)
        return {"undid": "new folder"}
    if kind == "trash":
        restored = [restore_one(n) for n in entry[1]]
        return {"undid": "trash", "paths": restored}
    if kind == "restore":
        for p in entry[1]:
            trash_one(p)
        return {"undid": "restore"}
    raise Refused("Nothing to undo")


OPS = {
    "rename": lambda r: op_rename(r["path"], r["name"]),
    "mkdir": lambda r: op_mkdir(r["parent"], r.get("name", "Untitled folder")),
    "trash": lambda r: op_trash(r["paths"]),
    "restore": lambda r: op_restore(r["names"]),
    "delete": lambda r: op_delete(r["paths"]),
    "empty": lambda r: op_empty(),
    "trashlist": lambda r: op_trashlist(),
    "undo": lambda r: op_undo(),
}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except ValueError:
            continue
        rid = request.get("id")
        op = OPS.get(request.get("op"))
        if op is None:
            emit(id=rid, ok=False, error="Unknown operation")
            continue
        try:
            result = op(request)
        except Refused as why:
            emit(id=rid, ok=False, error=str(why))
        except PermissionError:
            emit(id=rid, ok=False, error="Not allowed: no permission for that")
        except OSError as err:
            emit(id=rid, ok=False, error=err.strerror or str(err))
        else:
            emit(id=rid, ok=True, op=request.get("op"), **result)


if __name__ == "__main__":
    main()

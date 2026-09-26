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
restore, a restore as a trash, a copy as the removal of the copies, a
move as the move back.

Copy and move run on a thread of their own, so the main loop keeps
reading: a conflict is reported and the transfer waits for the answer, a
cancel is honoured between chunks. Progress goes out as events carrying
the request's id; the last line for that id carries `ok`.
"""
import datetime
import json
import os
import queue
import shutil
import sys
import threading
import time
import urllib.parse

HOME = os.path.expanduser("~")
TRASH = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"), "Trash")
TRASH_FILES = os.path.join(TRASH, "files")
TRASH_INFO = os.path.join(TRASH, "info")

journal = []
emit_lock = threading.Lock()


def emit(**obj):
    with emit_lock:
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
    if kind == "copy":
        for _, target in entry[1]:
            if os.path.lexists(target):
                remove(target)
        return {"undid": "copy"}
    if kind == "move":
        for src, target in reversed(entry[1]):
            if os.path.lexists(src):
                raise Refused(f"Cannot undo: {os.path.basename(src)} exists again")
            move(target, src)
        return {"undid": "move"}
    raise Refused("Nothing to undo")


# --- copy and move ----------------------------------------------------------

CHUNK = 1 << 20
transfer = None


class Cancelled(Exception):
    pass


def size_of(path):
    if os.path.islink(path):
        return 0
    if os.path.isdir(path):
        total = 0
        for folder, _, files in os.walk(path):
            for name in files:
                try:
                    total += os.lstat(os.path.join(folder, name)).st_size
                except OSError:
                    pass
        return total
    try:
        return os.lstat(path).st_size
    except OSError:
        return 0


def describe(path):
    try:
        st = os.lstat(path)
    except OSError:
        return {"size": 0, "modified": ""}
    return {"size": size_of(path) if os.path.isdir(path) else st.st_size,
            "modified": datetime.datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%dT%H:%M:%S"),
            "folder": os.path.isdir(path) and not os.path.islink(path)}


class Transfer(threading.Thread):
    """One copy or move of several things into one folder."""

    def __init__(self, rid, op, paths, dest):
        super().__init__(daemon=True)
        self.rid, self.op, self.paths, self.dest = rid, op, paths, dest
        self.answers = queue.Queue()
        self.cancelled = False
        self.policy = None          # a choice made "for all remaining"
        self.done = 0
        self.total = 0
        self.current = ""
        self.index = 0
        self.reported = 0.0

    def run(self):
        global transfer
        results = []
        target = None
        try:
            if not os.path.isdir(self.dest):
                raise Refused("The destination folder does not exist")
            self.total = sum(size_of(p) for p in self.paths)
            self.report(force=True)
            for i, src in enumerate(self.paths):
                if self.cancelled:
                    break
                self.index = i
                self.current = name = os.path.basename(src.rstrip("/"))
                target = os.path.join(self.dest, name)
                if os.path.abspath(src) == os.path.abspath(target):
                    if self.op == "move":
                        continue
                    target = os.path.join(self.dest, unique(self.dest, name))
                elif os.path.lexists(target):
                    choice = self.resolve(src, target, len(self.paths) - i - 1)
                    if choice == "skip":
                        self.done += size_of(src)
                        self.report(force=True)
                        continue
                    if choice == "keep":
                        target = os.path.join(self.dest, unique(self.dest, name))
                    elif choice == "replace":
                        remove(target)
                if self.op == "move" and os.lstat(src).st_dev == os.stat(self.dest).st_dev:
                    os.rename(src, target)
                    self.done += size_of(target)
                    self.report(force=True)
                else:
                    self.copy_tree(src, target)
                    if self.op == "move":
                        remove(src)
                    self.report(force=True)
                results.append((src, target))
                target = None
        except Cancelled:
            if target is not None and os.path.lexists(target):
                remove(target)
            self.finish(results, cancelled=True)
            return
        except Refused as why:
            emit(id=self.rid, ok=False, error=str(why))
            transfer = None
            return
        except PermissionError:
            emit(id=self.rid, ok=False, error="Not allowed: no permission for that")
            transfer = None
            return
        except OSError as err:
            emit(id=self.rid, ok=False, error=err.strerror or str(err))
            transfer = None
            return
        self.finish(results, cancelled=self.cancelled)

    def finish(self, results, cancelled):
        global transfer
        if results:
            journal.append((self.op, results))
        emit(id=self.rid, ok=True, op=self.op, count=len(results), cancelled=cancelled)
        transfer = None

    def resolve(self, src, target, remaining):
        if self.policy:
            return self.policy
        emit(id=self.rid, event="conflict", name=os.path.basename(target),
             existing=describe(target), incoming=describe(src), remaining=remaining)
        answer = self.answers.get()
        if self.cancelled:
            raise Cancelled()
        choice = answer.get("choice", "skip")
        if answer.get("all"):
            self.policy = choice
        return choice

    def report(self, force=False):
        now = time.monotonic()
        if not force and now - self.reported < 0.1:
            return
        self.reported = now
        emit(id=self.rid, event="progress", done=self.done, total=self.total,
             file=self.current, index=self.index, count=len(self.paths))

    def copy_tree(self, src, dst):
        if self.cancelled:
            raise Cancelled()
        if os.path.islink(src):
            os.symlink(os.readlink(src), dst)
        elif os.path.isdir(src):
            os.makedirs(dst, exist_ok=True)
            for name in os.listdir(src):
                self.copy_tree(os.path.join(src, name), os.path.join(dst, name))
            shutil.copystat(src, dst)
        else:
            with open(src, "rb") as fi, open(dst, "wb") as fo:
                while True:
                    if self.cancelled:
                        raise Cancelled()
                    buf = fi.read(CHUNK)
                    if not buf:
                        break
                    fo.write(buf)
                    self.done += len(buf)
                    self.report()
            shutil.copystat(src, dst)


def op_transfer(request):
    global transfer
    if transfer is not None and transfer.is_alive():
        raise Refused("Another copy is still running")
    transfer = Transfer(request["id"], request["op"], request["paths"], request["to"])
    transfer.start()
    return None            # the thread answers, when it is done


# Neither answers on its own: the transfer's final line is the answer, and
# these carry its id.
def op_answer(request):
    if transfer is not None:
        transfer.answers.put({"choice": request.get("choice"), "all": bool(request.get("all"))})
    return None


def op_cancel(request):
    if transfer is not None:
        transfer.cancelled = True
        transfer.answers.put({})
    return None


OPS = {
    "copy": op_transfer,
    "move": op_transfer,
    "answer": op_answer,
    "cancel": op_cancel,
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
            if result is not None:
                emit(id=rid, ok=True, op=request.get("op"), **result)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Files from a phone, over Bluetooth: the "Bluetooth" entry in an Android
share sheet, pointed at this computer.

obexd does the receiving. What it will not do on its own is decide whether
to take a file: it asks an agent, and while none is registered it refuses
everything (system/obex-object-push.conf relies on that). This is the agent.
BluetoothReceive.qml keeps it alive.

Each offer is a question in a notification - who is sending, what, how big
- with Accept and Decline. obexd waits a minute for the answer and then
gives up, which closes the question. What is refused never touches the disk:

- anything from a device that is not paired, without asking;
- anything that would not fit on the disk.

A name is cut to its last part, loses control characters and leading dots,
and never replaces a file: `photo.jpg` becomes `photo 2.jpg` if need be.
A file arrives in obexd's own folder and moves to ~/Downloads once whole;
nothing is ever opened by itself.

A phone sends several files as one session, one file after another, and
asks about each. Accepting the first accepts the rest of that session from
that same phone: one question per share, not one per photo. While it runs,
one notification follows it; when the session ends, a new one says what
came of it, so that it shows even after the first has gone to the centre.
Its buttons carry what they are about ("open:<path>", "show"), so they
still work after this process has been restarted.

Talks to QML in JSON lines on stdout: {"event": "ready"} once registered,
{"event": "show", "path": ...} for a notification's "Show in Files", and
{"event": "open", "path": ...} for a click on one about a single file.
"""
import json
import os
import re
import shutil
import signal
import sys
import time

from jeepney import DBusAddress, HeaderFields, MatchRule, MessageType, message_bus, new_error, new_method_call, new_method_return
from jeepney.io.blocking import Proxy, open_dbus_connection
from jeepney.wrappers import DBusErrorResponse, unwrap_msg

OBEX = "org.bluez.obex"
AGENT = "/org/groma/obex/agent"
REJECTED = "org.bluez.obex.Error.Rejected"
PROPS = "org.freedesktop.DBus.Properties"
NOTIFY = DBusAddress("/org/freedesktop/Notifications", bus_name="org.freedesktop.Notifications",
                     interface="org.freedesktop.Notifications")
DOWNLOADS = os.path.join(os.path.expanduser("~"), "Downloads")
# obexd writes only under its root folder (the -r in
# system/obex-object-push.conf): a file goes there while it arrives, and
# moves to Downloads once whole. A part-file never shows in Downloads.
INCOMING = os.path.join(os.path.expanduser("~"), ".local", "share", "groma", "obex")


def emit(**obj):
    print(json.dumps(obj), flush=True)


def log(*words):
    print(*words, file=sys.stderr, flush=True)


def safe_name(name):
    name = os.path.basename((name or "").replace("\\", "/"))
    name = re.sub(r"[\x00-\x1f\x7f]", "", name).strip().lstrip(".").strip()
    return name[:200] or "Received file"


def unique(folder, name):
    """`name` if nothing in `folder` has it, else `name 2`, `name 3`, ... with
    the extension kept on the end. The same rule as Files."""
    if not os.path.lexists(os.path.join(folder, name)):
        return name
    stem, ext = os.path.splitext(name)
    n = 2
    while os.path.lexists(os.path.join(folder, f"{stem} {n}{ext}")):
        n += 1
    return f"{stem} {n}{ext}"


def size_text(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1000 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1000


def paired_device(address):
    """bluez's name for a paired device at `address`, or None."""
    try:
        with open_dbus_connection(bus="SYSTEM") as conn:
            objects, = unwrap_msg(conn.send_and_get_reply(new_method_call(
                DBusAddress("/", bus_name="org.bluez", interface="org.freedesktop.DBus.ObjectManager"),
                "GetManagedObjects"), timeout=5))
    except (OSError, DBusErrorResponse, TimeoutError) as err:
        log("bluez:", repr(err))
        return None
    for ifaces in objects.values():
        device = ifaces.get("org.bluez.Device1")
        if device and device.get("Address", ("", ""))[1].upper() == address.upper():
            if not device.get("Paired", ("b", False))[1]:
                return None
            return device.get("Alias", ("s", ""))[1] or device.get("Name", ("s", ""))[1] or address
    return None


class Agent:
    def __init__(self):
        self.conn = open_dbus_connection(bus="SESSION")
        # Waiting for its answer: {notification id: offer}.
        self.offers = {}
        # Sessions whose first file was accepted: {session path: address}.
        self.trusted = {}
        # Files on their way: {transfer path: receiving}.
        self.receiving = {}
        # One notification per session, replaced as it goes: {session path: state}.
        self.sessions = {}
        # What a notification's buttons are about: {notification id: action}.
        self.done = {}
        self.serial = 0
        # Whatever a crash or a restart left half-arrived is no use now.
        if os.path.isdir(INCOMING):
            for name in os.listdir(INCOMING):
                part = os.path.join(INCOMING, name)
                if os.path.isfile(part) and not os.path.islink(part):
                    os.unlink(part)

    def call(self, address, method, signature=None, body=(), timeout=10):
        return unwrap_msg(self.conn.send_and_get_reply(
            new_method_call(address, method, signature, body), timeout=timeout))

    def get(self, path, interface, name):
        value, = self.call(DBusAddress(path, bus_name=OBEX, interface=PROPS), "Get", "ss", (interface, name))
        return value[1]

    def notify(self, summary, body, actions=(), urgency=1, replaces=0):
        try:
            nid, = self.call(NOTIFY, "Notify", "susssasa{sv}i",
                             ("Groma", replaces, "bluetooth", summary, body, list(actions),
                              {"urgency": ("y", urgency), "category": ("s", "transfer")}, -1))
            return nid
        except (DBusErrorResponse, TimeoutError) as err:
            log("notify:", repr(err))
            return 0

    def close_notification(self, nid):
        try:
            self.call(NOTIFY, "CloseNotification", "u", (nid,))
        except (DBusErrorResponse, TimeoutError):
            pass

    # --- the agent's methods ---------------------------------------------

    def on_call(self, msg):
        member = msg.header.fields.get(HeaderFields.member)
        if member == "AuthorizePush":
            self.authorize(msg)
        elif member == "Cancel":
            # obexd stopped waiting: the minute ran out, or the phone gave up.
            for nid, offer in list(self.offers.items()):
                del self.offers[nid]
                self.close_notification(nid)
                self.notify(f"Missed a file from {offer['device']}", offer["name"])
            self.reply(msg)
        elif member == "Release":
            self.reply(msg)
            log("obexd released the agent")
            sys.exit(0)
        else:
            self.conn.send(new_error(msg, "org.freedesktop.DBus.Error.UnknownMethod"))

    def reply(self, msg, signature=None, body=()):
        try:
            self.conn.send(new_method_return(msg, signature, body))
        except OSError as err:
            log("reply:", repr(err))

    def refuse(self, msg):
        self.conn.send(new_error(msg, REJECTED))

    def authorize(self, msg):
        transfer, = msg.body
        try:
            session = self.get(transfer, "org.bluez.obex.Transfer1", "Session")
            address = self.get(session, "org.bluez.obex.Session1", "Destination")
            offered = self.get(transfer, "org.bluez.obex.Transfer1", "Name")
            try:
                size = self.get(transfer, "org.bluez.obex.Transfer1", "Size")
            except DBusErrorResponse:
                size = None
        except (DBusErrorResponse, TimeoutError) as err:
            log("authorize:", repr(err))
            self.refuse(msg)
            return

        device = paired_device(address)
        if device is None:
            log(f"refused a file from {address}: not a paired device")
            self.refuse(msg)
            return

        name = safe_name(offered)
        os.makedirs(DOWNLOADS, exist_ok=True)
        if size is not None and size > shutil.disk_usage(DOWNLOADS).free:
            self.refuse(msg)
            self.notify(f"No room for {name}", f"{device} offered {size_text(size)}, more than the disk has free.")
            return

        offer = {"msg": msg, "transfer": transfer, "session": session, "address": address,
                 "device": device, "name": name, "size": size}

        # The rest of a share already accepted.
        if self.trusted.get(session) == address:
            self.accept(offer)
            return

        what = name + (f" · {size_text(size)}" if size is not None else "")
        nid = self.notify(f"{device} wants to send a file", what,
                          ["accept", "Accept", "decline", "Decline"], urgency=2)
        if nid == 0:
            self.refuse(msg)
            return
        self.offers[nid] = offer

    def accept(self, offer):
        # Numbered, so two arrivals never share a name - and none is ever
        # vcard.vcf, the one file Object Push hands out from this folder.
        self.serial += 1
        os.makedirs(INCOMING, exist_ok=True)
        arriving = os.path.join(INCOMING, f"{self.serial}-{offer['name']}")
        self.trusted[offer["session"]] = offer["address"]
        self.receiving[offer["transfer"]] = {"session": offer["session"], "arriving": arriving,
                                             "name": offer["name"], "size": offer["size"],
                                             "device": offer["device"], "shown": 0.0}
        self.reply(offer["msg"], "s", (arriving,))
        state = self.sessions.setdefault(offer["session"], {"nid": 0, "got": [], "lost": [],
                                                            "device": offer["device"]})
        state["nid"] = self.notify(f"Receiving from {offer['device']}", offer["name"],
                                   replaces=state["nid"])

    # --- what the notifications and obexd say -----------------------------

    def on_signal(self, msg):
        member = msg.header.fields.get(HeaderFields.member)
        if member == "ActionInvoked":
            nid, key = msg.body
            self.answered(nid, key)
        elif member == "NotificationClosed":
            nid, _ = msg.body
            if nid in self.offers:
                self.answered(nid, "decline")
        elif member == "PropertiesChanged":
            path = msg.header.fields.get(HeaderFields.path)
            if path in self.receiving:
                self.progress(path, msg.body[1])
        elif member == "InterfacesRemoved":
            path, _ = msg.body
            # A transfer obexd dropped without saying how it ended: it
            # refused to write, or the phone went. Then the phone's share
            # itself ends, and that is when to say what came of it.
            if path in self.receiving:
                self.lost(path)
            if path in self.sessions:
                self.finish(path)
        elif member == "NameOwnerChanged":
            name, old, new = msg.body
            if name == OBEX and old and not new:
                log("obexd went away")
                sys.exit(1)

    def answered(self, nid, key):
        offer = self.offers.pop(nid, None)
        if offer is not None:
            if key == "accept":
                self.accept(offer)
            else:
                self.refuse(offer["msg"])
            return
        # The buttons carry what they are about, so they still work for an
        # agent that did not post them - after a restart, say. A click on
        # the notification itself opens the one file it names, if this
        # agent posted it, and Downloads otherwise.
        if key == "show":
            emit(event="show", path=DOWNLOADS)
        elif key.startswith("open:"):
            self.open(key[5:])
        elif key == "default" and nid in self.done:
            got = self.done[nid]
            if len(got) == 1:
                self.open(got[0])
            else:
                emit(event="show", path=DOWNLOADS)
        elif key == "default":
            emit(event="show", path=DOWNLOADS)

    def open(self, path):
        # Only something this agent put there: the key is a string anyone
        # on the session bus could have sent.
        real = os.path.realpath(path)
        if os.path.dirname(real) == os.path.realpath(DOWNLOADS) and os.path.isfile(real):
            emit(event="open", path=real)

    def progress(self, path, changed):
        file = self.receiving[path]
        state = self.sessions.get(file["session"], {"nid": 0, "got": []})
        status = changed.get("Status", (None, ""))[1]
        if status == "complete":
            del self.receiving[path]
            os.makedirs(DOWNLOADS, exist_ok=True)
            target = os.path.join(DOWNLOADS, unique(DOWNLOADS, file["name"]))
            try:
                shutil.move(file["arriving"], target)
            except OSError as err:
                log("move:", repr(err))
                state["lost"].append(file["name"])
                return
            state["got"].append(target)
            count = len(state["got"])
            state["nid"] = self.notify(f"Receiving from {file['device']}",
                                       os.path.basename(target) if count == 1 else f"{count} files so far",
                                       replaces=state["nid"])
        elif status == "error":
            self.lost(path)
        elif "Transferred" in changed and file["size"]:
            now = time.monotonic()
            if now - file["shown"] >= 2:
                file["shown"] = now
                done = changed["Transferred"][1]
                state["nid"] = self.notify(f"Receiving from {file['device']}",
                                           f"{file['name']} · {size_text(done)} of {size_text(file['size'])}",
                                           replaces=state["nid"])

    def lost(self, path):
        file = self.receiving.pop(path)
        # obexd leaves what had arrived; half a file is no use to anyone.
        try:
            os.unlink(file["arriving"])
        except OSError:
            pass
        self.sessions[file["session"]]["lost"].append(file["name"])

    def finish(self, session):
        """The phone's share is over: one notification for all of it, posted
        new rather than replacing the progress, so that it shows."""
        state = self.sessions.pop(session)
        self.trusted.pop(session, None)
        self.close_notification(state["nid"])
        got, lost, device = state["got"], state["lost"], state["device"]
        missed = f" · {len(lost)} did not arrive" if got and lost else ""
        if len(got) == 1:
            nid = self.notify(f"Received {os.path.basename(got[0])}", f"From {device} · in Downloads{missed}",
                              ["open:" + got[0], "Open", "show", "Show in Files"])
        elif got:
            nid = self.notify(f"Received {len(got)} files", f"From {device} · in Downloads{missed}",
                              ["show", "Show in Files"])
        elif lost:
            what = lost[0] if len(lost) == 1 else f"{len(lost)} files"
            nid = self.notify(f"Did not receive {what}", f"{device} stopped sending.")
        else:
            return
        self.done[nid] = got

    # --- the loop ---------------------------------------------------------

    def run(self):
        conn = self.conn
        # filter() hands back a handle; the messages collect in its queue.
        calls = conn.filter(MatchRule(type="method_call", path=AGENT)).queue
        signals = conn.filter(MatchRule(type="signal")).queue
        bus = Proxy(message_bus, conn)
        bus.AddMatch(MatchRule(type="signal", sender=OBEX, interface=PROPS, member="PropertiesChanged",
                               path_namespace="/org/bluez/obex"))
        bus.AddMatch(MatchRule(type="signal", interface="org.freedesktop.Notifications",
                               path="/org/freedesktop/Notifications"))
        bus.AddMatch(MatchRule(type="signal", sender=OBEX, interface="org.freedesktop.DBus.ObjectManager",
                               member="InterfacesRemoved"))
        owner = MatchRule(type="signal", sender="org.freedesktop.DBus", member="NameOwnerChanged")
        owner.add_arg_condition(0, OBEX)
        bus.AddMatch(owner)

        try:
            self.call(DBusAddress("/org/bluez/obex", bus_name=OBEX, interface="org.bluez.obex.AgentManager1"),
                      "RegisterAgent", "o", (AGENT,), timeout=30)
        except DBusErrorResponse as err:
            # AlreadyExists: another program (Blueman, GNOME) is the agent.
            log("could not register:", err.name, err.data)
            sys.exit(2)
        emit(event="ready")

        while True:
            conn.recv_messages()
            while calls:
                self.on_call(calls.popleft())
            while signals:
                msg = signals.popleft()
                if msg.header.message_type == MessageType.signal:
                    self.on_signal(msg)


def die_with_parent():
    """obexd takes one agent. One left running by a shell that died would
    keep the next shell's from registering, so this one goes with its
    parent: the kernel sends SIGTERM when the shell exits."""
    try:
        import ctypes
        PR_SET_PDEATHSIG = 1
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except OSError:
        pass
    if os.getppid() == 1:
        sys.exit(0)


if __name__ == "__main__":
    die_with_parent()
    try:
        Agent().run()
    except (OSError, EOFError) as err:
        log("lost the bus:", repr(err))
        sys.exit(1)

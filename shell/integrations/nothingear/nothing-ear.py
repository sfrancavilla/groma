#!/usr/bin/env python3
"""Talk to a pair of Nothing earbuds over their vendor channel.

Run by NothingEar.qml with the device address; prints one JSON object per
line. Bluez gives one battery number for the pair; the buds themselves give
left, right and case, and announce it whenever it changes. They also send a
"wear changed" event when a bud goes in or out - with no direction in it, and
no query that returns the state (measured 2026-09-25, every GET identical bud
out vs in), so it is reported as a bare event and the shell decides what a
bare event is worth.

The protocol facts - RFCOMM channel 15, the frame layout
55|60 01|cmd|dir|len u16|seq|payload|crc16-arc, the command numbers and the
battery payload - come from EarA-linux by oneydef
(https://github.com/oneydef/EarA-linux), the community's decode of the Ear (2)
protocol, confirmed here against an Ear (3). This file is Groma's own code,
written from those facts; EarA-linux itself is GPL-3.0 and none of its code is
copied here.
"""
import json, signal, socket, sys, time

ADDR = sys.argv[1]
CH = 15
BATTERY_EVERY = 300          # the buds only announce battery on change

def crc16_arc(data):
    crc = 0xFFFF             # init 0 does not match what the buds check
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc & 0xFFFF

def frame(cmd, seq, payload=b"", direction=0xC0):
    body = bytes([0x55, 0x60, 0x01, cmd, direction, len(payload) & 0xFF,
                  len(payload) >> 8, seq & 0xFF]) + payload
    crc = crc16_arc(body)
    return body + bytes([crc & 0xFF, crc >> 8])

def emit(**obj):
    print(json.dumps(obj), flush=True)

COMPONENT = {2: "left", 3: "right", 4: "case", 6: "headset"}

def parse_battery(payload):
    out = {}
    if not payload:
        return out
    count = payload[0]
    for i in range(count):
        at = 1 + i * 2
        if at + 1 >= len(payload):
            break
        component, raw = payload[at], payload[at + 1]
        level = raw & 0x7F
        if level > 100:
            continue
        entry = {"level": level, "charging": bool(raw & 0x80)}
        if component == 1:               # one value for both buds
            out["left"] = out["right"] = entry
        elif component in COMPONENT:
            out[COMPONENT[component]] = entry
    return out

def handle(cmd, direction, payload):
    if cmd == 0x07 and direction == 0x40 or cmd == 0x01 and direction == 0xE0:
        emit(event="battery", **parse_battery(payload))
    elif cmd == 0x03 and direction == 0xE0:
        emit(event="wear")

signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

# One attempt, and exit on any loss. No retry loop: an RFCOMM connect to a
# device that is not connected makes bluez page it, so a helper that keeps
# retrying keeps re-establishing a link the user just closed - with nothing
# but this channel on it, and no audio. The shell restarts this only while
# the buds are its audio device, which is the one condition under which
# opening the channel cannot be the thing that connected them.
sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
sock.settimeout(8)
try:
    sock.connect((ADDR, CH))
except OSError as err:
    emit(event="failed", reason=str(err))
    sys.exit(0)

emit(event="connected")
seq = 1
sock.send(frame(0x07, seq))
sock.settimeout(1)
buf = b""
next_battery = time.time() + BATTERY_EVERY
try:
    while True:
        try:
            chunk = sock.recv(512)
            if not chunk:
                emit(event="lost", reason="closed by device")
                break
            buf += chunk
        except socket.timeout:
            pass

        # Frames can arrive split or back to back.
        while True:
            start = buf.find(b"\x55")
            if start < 0 or len(buf) - start < 8:
                break
            buf = buf[start:]
            length = buf[5] | (buf[6] << 8)
            total = 8 + length + 2
            if len(buf) < total:
                break
            pkt, buf = buf[:total], buf[total:]
            if crc16_arc(pkt[:-2]) == (pkt[-2] | (pkt[-1] << 8)):
                handle(pkt[3], pkt[4], pkt[8:-2])

        if time.time() >= next_battery:
            seq = (seq + 1) & 0xFF
            sock.send(frame(0x07, seq))
            next_battery = time.time() + BATTERY_EVERY
except OSError as err:
    emit(event="lost", reason=str(err))
finally:
    sock.close()
